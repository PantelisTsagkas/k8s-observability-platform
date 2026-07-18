# CLAUDE.md: k8s-observability-platform

Guidance for Claude Code when working in this repository.

## What this project is

A Kubernetes platform project for a DevOps/cloud portfolio. It takes an existing, already-instrumented FastAPI observability app (separate repo: observability-simulator) and runs it on Kubernetes, first locally on k3d, then on AWS EKS via Terraform. It adds one small companion service (a load generator) so the cluster has multi-service traffic worth observing.

This is a deployment/platform repo. The main application lives in its own repo and is consumed here as a container image. The only application code in this repo is the load generator, which is intentionally small.

Owner context: the author is learning Kubernetes. Explain the "why" behind manifests and Helm values in comments and commit messages. Do not silently generate large amounts of YAML without explanation.

## Repository layout

```
k8s-observability-platform/
├── CLAUDE.md
├── README.md
├── apps/
│   └── loadgen/              # Companion service, Python, ~100 lines
│       ├── pyproject.toml
│       ├── src/loadgen/
│       └── tests/
├── manifests/                # Phase 0: raw YAML, written by hand, kept for reference
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── ingress.yaml
│   └── hpa.yaml
├── charts/
│   └── obs-sim/              # Phase 1: Helm chart for the app + loadgen
├── gitops/
│   └── argocd/               # Phase 2: ArgoCD Application definitions
├── terraform/
│   ├── eks/                  # Phase 3: VPC + EKS + IRSA + ALB controller
│   └── modules/
├── .github/workflows/
└── docs/                     # Screenshots, EKS writeup, decisions
```

## Phases

Work strictly in phase order. Do not start a phase until the previous one is verified working.

### Phase 0: Raw Kubernetes on k3d (current)

Goal: run the observability app on a local cluster using hand-written manifests. No Helm.

- Cluster: k3d (chosen over kind for speed and built-in load balancer on macOS).
- Write plain manifests: Namespace, Deployment, Service, ConfigMap, Ingress, HPA.
- Container image for the app is pulled from GHCR (built in the app's own repo).
- Verify: app reachable via Ingress, /metrics endpoint scrapeable, HPA reacts to load.
- Every manifest gets a short comment block explaining what it does and why each non-obvious field is set.

Definition of done: `k3d cluster create` + `kubectl apply -f manifests/` brings up a working app from scratch, documented in README.

### Phase 1: Helm + observability stack

Goal: replace raw manifests with a Helm chart, install the monitoring stack the production way.

- Package app + loadgen as one chart (`charts/obs-sim`) with values for image tag, replicas, resources.
- Install kube-prometheus-stack via Helm. Use a ServiceMonitor to scrape the app.
- Install Loki + Promtail (or Alloy if Promtail is deprecated at time of work: check current Grafana docs) for log collection.
- Keep `manifests/` in place as a learning artifact, marked as superseded in README.

Definition of done: Grafana shows app metrics and logs, everything installed via Helm, zero `kubectl apply` of raw YAML.

### Phase 2: GitOps with ArgoCD

Goal: commit-to-deployed with no manual steps.

- Install ArgoCD on the cluster, define Applications in `gitops/argocd/`.
- GitHub Actions in the app repo: build image, push to GHCR, bump the tag in this repo (PR or direct commit, decide and document the tradeoff).
- ArgoCD auto-syncs the chart.

Definition of done: a code change in the app repo lands in the cluster with no kubectl or helm commands run by a human.

### Phase 3: EKS with Terraform

Goal: the same Helm charts running on AWS, provisioned with Terraform, then destroyed.

- Terraform: VPC, EKS (managed node group on spot instances), IRSA, AWS Load Balancer Controller, ECR or keep GHCR.
- Deploy the identical charts from Phase 1/2. The punchline: only the infrastructure layer changed.
- Budget discipline: EKS control plane is ~$0.10/hour. Build, verify, screenshot, `terraform destroy` the same day. Target total spend under £10.
- Capture screenshots and write docs/eks-writeup.md before destroying anything.

Definition of done: writeup + screenshots in docs/, `terraform destroy` completes clean, state confirms zero resources.

## Load generator (apps/loadgen)

- Python, managed with uv. Never pip or poetry.
- Small: hits the app's endpoints on a configurable interval with configurable concurrency, mixes in some 4xx/slow requests so dashboards show variety.
- Config via environment variables (TARGET_URL, RPS, ERROR_RATE), read into a Pydantic settings model.
- Type hints everywhere. Pytest for the request-mix logic (no network in tests, inject the HTTP client).
- Dockerfile: multi-stage, uv-based, non-root user.

## Conventions

- Conventional Commits (feat:, fix:, docs:, chore:). Scope by area, e.g. `feat(manifests): add HPA for obs-sim`.
- Explicit over clever. No YAML anchors or Helm template tricks unless they remove real duplication.
- Python: uv only, type hints required, pytest for tests.
- Terraform: fmt and validate before commit, pin provider versions, no hardcoded account IDs or regions (use variables).
- Never commit kubeconfig, AWS credentials, or Terraform state. State for Phase 3 goes in an S3 backend.
- README stays current per phase: what works now, how to run it, one architecture diagram.

## Things Claude Code should NOT do

- Do not skip ahead to Helm or Terraform while Phase 0 is in progress.
- Do not install operators or CRDs beyond what the current phase needs.
- Do not generate manifests without explanatory comments.
- Do not create AWS resources without being explicitly asked. Phase 3 costs money.
- Do not add a service mesh, external-dns, cert-manager, or other extras unless asked. Scope creep kills this project.

## Verification commands

```bash
# Phase 0
k3d cluster list
kubectl get pods -n obs-sim
kubectl top pods -n obs-sim          # requires metrics-server, bundled with k3d
curl -s localhost:8080/metrics | head

# Phase 1
helm list -A
kubectl get servicemonitors -A

# Phase 2
kubectl get applications -n argocd

# Phase 3
terraform -chdir=terraform/eks plan
aws eks list-clusters
```

## Current status

Phase 2 complete (2026-07-18): GitOps with ArgoCD. ArgoCD is installed via a
pinned `helm install` into an `argocd` namespace (values +Application under
`gitops/argocd/`, bootstrap documented in `gitops/argocd/README.md`). The
obs-sim chart is now reconciled from git, not `helm install`: the manual
Phase 1 release was `helm uninstall`ed first so ArgoCD is the sole reconciler.
The Application tracks `main` at `charts/obs-sim` with auto-sync (prune +
selfHeal). Commit-to-deployed proven live: an `RPS 2 -> 3` values change merged
via PR #5, ArgoCD polled git (~80s), updated the ConfigMap, and the
`checksum/config` annotation rolled the loadgen pod - zero helm/kubectl against
the cluster. Key live finding: the replicas trap did NOT bite. The chart's
Phase 1 decision to omit `spec.replicas` under HPA also satisfies ArgoCD's
built-in replicas normalizer, so no `ignoreDifferences` was needed (verified
Synced with live at replicas 2, git specifying none, after a hard refresh).
Cross-repo CI (observability-simulator builds image -> GHCR -> bumps sha- tag
here) is the named Phase 2 follow-up, deferred by choice.

Next: Phase 3, EKS with Terraform. Provision VPC + EKS + IRSA + ALB controller,
deploy the identical charts, screenshot, then `terraform destroy` the same day.

Phase 1 complete (2026-07-16): the observability stack is in, all via Helm.
kube-prometheus-stack, Loki (single-binary, filesystem), and Grafana Alloy
(DaemonSet log collector, the current replacement for the EOL Promtail) are
installed into a `monitoring` namespace. Values files live under
`monitoring/`. A ServiceMonitor in the chart
(`charts/obs-sim/templates/servicemonitor.yaml`) scrapes the app; Alloy ships
pod logs to Loki; a sidecar-provisioned ConfigMap
(`monitoring/loki-datasource.yaml`) registers Loki in Grafana. Verified end
to end: metrics and logs correlate on one time axis in Grafana Explore (an
`http_errors_total` rate spike lines up with the `500` log lines from
`/simulate/error`). Debugging findings from this phase are in the README
"Lessons" section (ServiceMonitor's three-selector chain, the `/health`
denominator dilution, the Loki `deploymentMode` docs drift).

Phase 1 chart (2026-07-15): charts/obs-sim written and deployed, hand-written
from the manifests rather than `helm create`. Parity proven with `kubectl
diff` against the live Phase 0 objects: four of six showed no diff, both
differences were real findings (imagePullPolicy defaulting, absent replicas).
manifests/ is superseded but kept as a learning artifact.

Phase 0 complete (2026-07-09): raw manifests on k3d, app via Ingress at
localhost:8080, HPA verified 2 -> 5 replicas under load (screenshots in
docs/). Both images multi-arch on GHCR, built by CI in their own repos.

Open cleanup seam (still open): the kube-prometheus-stack install was a bare
`helm install` with no values file; capturing it under `monitoring/` would make
the whole stack reproducible. Not blocking, and deliberately left outside
ArgoCD in Phase 2 (the phase DoD is the app, not the monitoring stack).
