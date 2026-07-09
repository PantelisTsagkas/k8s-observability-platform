# k8s-observability-platform

**Status: ACTIVE** - Phase 0 (raw Kubernetes on k3d) in progress.

Runs [observability-simulator](https://github.com/PantelisTsagkas/observability-simulator)
(an instrumented FastAPI app) on Kubernetes: first locally on k3d with
hand-written manifests, then packaged with Helm, deployed via ArgoCD, and
finally on AWS EKS provisioned with Terraform.

This is a deployment/platform repo. The application lives in its own repo and
is consumed here as a container image from GHCR. The only application code
here is a small load generator (`apps/loadgen`) that gives the cluster
multi-service traffic worth observing.

## Phases

| Phase | Goal | Status |
|-------|------|--------|
| 0 | Raw manifests on k3d: Deployment, Service, ConfigMap, Ingress, HPA | In progress |
| 1 | Helm chart + kube-prometheus-stack + Loki | Not started |
| 2 | GitOps with ArgoCD, commit-to-deployed | Not started |
| 3 | EKS with Terraform, deploy the same charts, destroy same day | Not started |

## Prerequisites

- docker, kubectl, k3d, helm (all via `brew install`)
- The app image is published by CI in the app repo:
  `ghcr.io/pantelistsagkas/observability-simulator:latest`

## Running (Phase 0)

Coming as the manifests land. Target:

```bash
k3d cluster create obs-platform
kubectl apply -f manifests/
```

## Layout

```
apps/loadgen/     # load generator (Python, uv)
manifests/        # Phase 0: hand-written YAML, one comment block per manifest
docs/             # screenshots, decisions, EKS writeup
```
