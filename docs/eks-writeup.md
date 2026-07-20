# Phase 3: the same charts on EKS, provisioned with Terraform

Status: DONE (built, verified, and destroyed 2026-07-20).

## The thesis, and whether it held

Phases 0-2 ran the observability app on a local k3d cluster: raw manifests, then
a Helm chart, then GitOps with ArgoCD. Phase 3 asked one question: can the
*identical* Helm chart run on real AWS EKS, with only the infrastructure layer
swapped?

It held. The obs-sim chart deployed to EKS unchanged in structure. The only
differences were values, captured in one overlay (`charts/obs-sim/values-eks.yaml`):

| Concern        | k3d (Phases 0-2)     | EKS (Phase 3)                         |
|----------------|----------------------|---------------------------------------|
| Ingress class  | `traefik`            | `alb`                                 |
| Ingress config | none                 | 3 ALB annotations (scheme/target/health) |
| ServiceMonitor | on (Prometheus stack)| off (app-only scope)                  |
| Metrics for HPA| bundled with k3d     | metrics-server installed manually     |

Everything else - the Deployment, Service, HPA, ConfigMap, the loadgen - was
byte-for-byte the chart from Phase 1. That is the entire point of the phase.

## What Terraform provisioned

`terraform/eks/`, using pinned community modules (`terraform-aws-modules/vpc`
`~> 6.0`, `/eks` `~> 21.0`):

- VPC across 2 AZs, **single NAT gateway** (the module default is one-per-AZ; the
  cost trap you ship by reflex if you copy a 3-AZ example), private-subnet nodes.
- EKS 1.33 control plane, `enable_cluster_creator_admin_permissions = true` so
  the Terraform identity gets a cluster-admin access entry and kubectl works
  immediately (v21 uses Access Entries, not the legacy aws-auth ConfigMap).
- One spot managed node group (2x t3.medium).
- IRSA role for the AWS Load Balancer Controller, trust scoped to exactly
  `kube-system:aws-load-balancer-controller`.

Terraform deliberately owns AWS only. metrics-server, the LB controller, and the
app were installed with `helm` afterward, so `terraform destroy` never needs to
authenticate to a cluster it is deleting (the most common way a first EKS
teardown hangs). State was local by design - the cluster is same-day ephemeral,
so nothing needed to survive the destroy.

## Verified live

- App reachable over the internet via an internet-facing ALB:
  `curl http://<alb-hostname>/health` -> `{"status":"healthy"}`, `/metrics`
  served Prometheus output.
- HPA read `cpu: 11%/70%` (a real utilisation figure, not `<unknown>`), proving
  metrics-server was scraping - the HPA was live, not inert.
- 2 Ready nodes, 2 app replicas + loadgen, `aws-node`/coredns/kube-proxy healthy.

## Lessons (the two things that actually broke)

### 1. Addon ordering is load-bearing: the CNI deadlock

The first `apply` hung, then the node group failed to become ACTIVE. Root cause:
this EKS module sets `bootstrap_self_managed_addons = false`, so EKS does **not**
ship a CNI on its own - Terraform is the only source of `vpc-cni`. By default the
module installs addons *after* the node group. That produces a deadlock:

```
node group waits for nodes to be Ready
    -> nodes need a CNI to be Ready
        -> the CNI is scheduled to install AFTER the node group
            -> nobody moves
```

Nodes sat `NotReady` with `cni plugin not initialized`, and kube-system had zero
pods. `terraform validate` cannot catch this - it is a runtime ordering fact, not
a syntax one. The fix is one attribute:

```hcl
addons = {
  vpc-cni    = { before_compute = true }   # CNI must exist BEFORE nodes join
  kube-proxy = { before_compute = true }
  coredns    = {}                          # needs a Ready node, so it goes after
}
```

With that, `vpc-cni` and `kube-proxy` install first, nodes get networking, the
node group reaches ACTIVE. This is the canonical `terraform-aws-modules/eks`
gotcha on clusters that don't self-bootstrap the CNI.

### 2. Short-lived SSO tokens vs long-running applies

The account authenticates through IAM Identity Center (SSO), and the session is
short-lived. The ~15-minute control-plane + node-group wait outlived the token,
and `apply` died mid-wait with `ExpiredTokenException`. The fix was to
re-authenticate with the real SSO workflow (`aws sso login --profile ...`, not
the generic `aws login` IAM-user flow) and re-run. Terraform picked up where it
left off; the already-failed node group was simply replaced. Lesson: for EKS,
start the session on a fresh token, and know your auth is SSO, not IAM-user.

### 3. "className: alb" is not a drop-in for traefik

An ALB ingress needs annotations traefik never did. Missing them fails silently:
`scheme: internet-facing` (else the ALB is internal and unreachable from the
laptop), `target-type: ip` (the Service is ClusterIP; the default `instance`
mode needs a NodePort), and `healthcheck-path: /health` (the default `/` may not
return 200, leaving targets unhealthy and the ALB returning 502). All three live
in `values-eks.yaml` behind a backward-compatible annotations passthrough, so the
k3d/ArgoCD path renders nothing new.

## Teardown

Ordered to avoid orphaning the ALB (which Terraform does not track): delete the
app ingress first, confirm the ALB disappears, then uninstall the controller,
then `terraform destroy`, then verify zero. See `docs/eks-runbook.md`.
