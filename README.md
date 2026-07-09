# k8s-observability-platform

**Status: ACTIVE** - Phase 0 complete, Phase 1 (Helm + observability stack) next.

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
| 0 | Raw manifests on k3d: Deployment, Service, ConfigMap, Ingress, HPA | Done |
| 1 | Helm chart + kube-prometheus-stack + Loki | Not started |
| 2 | GitOps with ArgoCD, commit-to-deployed | Not started |
| 3 | EKS with Terraform, deploy the same charts, destroy same day | Not started |

## Architecture (Phase 0)

```
localhost:8080
      |
k3d loadbalancer (host port 8080 -> cluster port 80)
      |
Traefik ingress controller (bundled with k3s)
      |
Service obs-sim (ClusterIP, selects app=obs-sim pods)
      |
Deployment obs-sim (2-6 replicas, managed by HPA)
      ^
Deployment loadgen (mixed success/error/slow traffic,
                    tuned via ConfigMap loadgen-config)
```

Both images are multi-arch (amd64 + arm64), built and pushed to GHCR by CI:
`ghcr.io/pantelistsagkas/observability-simulator` from the app repo, and
`ghcr.io/pantelistsagkas/obs-loadgen` from this repo.

## Running (Phase 0)

Prerequisites: docker, kubectl, k3d (all via `brew install`).

```bash
# The port mapping is load-bearing: it maps localhost:8080 to the
# cluster's ingress controller, which is how the app is reached.
k3d cluster create obs-platform --agents 2 --port "8080:80@loadbalancer"

kubectl apply -f manifests/

# Wait for everything to come up
kubectl get pods -n obs-sim -w
```

Verify:

```bash
curl -s localhost:8080/health          # {"status":"healthy"}
curl -s localhost:8080/metrics | head  # Prometheus metrics, counters climbing
kubectl get hpa -n obs-sim             # cpu utilization vs 70% target
kubectl logs deployment/loadgen -n obs-sim --tail 5   # traffic mix in action
```

To watch the HPA scale, raise the load (edit `manifests/configmap.yaml`,
set `RPS: "300"` and `CONCURRENCY: "50"`), then:

```bash
kubectl apply -f manifests/configmap.yaml
kubectl rollout restart deployment/loadgen -n obs-sim   # env is read at start
kubectl get hpa -n obs-sim -w
```

![HPA scaling from 2 to 5 replicas under load](docs/phase-0-hpa-scaling.png)

Teardown: `k3d cluster delete obs-platform`.

## Layout

```
apps/loadgen/     # load generator (Python, uv, tested with pytest)
manifests/        # Phase 0: hand-written YAML, one comment block per manifest
docs/             # screenshots, decisions, EKS writeup (Phase 3)
```

## Lessons that cost debugging time (Phase 0)

- `runAsNonRoot: true` needs a *numeric* `USER` in the Dockerfile; the kubelet
  cannot verify a username, and fails with `CreateContainerConfigError`.
- A wrong `containerPort` broke both probes at once via the named port, and
  the liveness probe kept killing a perfectly healthy app. `kubectl describe`
  events tell the real story; `kubectl get pods` only says something is wrong.
- Env vars from a ConfigMap are read at container start. Editing the
  ConfigMap does nothing until `kubectl rollout restart`.
- Images built on GitHub's amd64 runners will not run on arm64 (Apple
  Silicon) nodes unless CI builds multi-arch with QEMU.
- Load generators have bottlenecks too: with 10% slow requests holding
  semaphore slots, concurrency 5 caps effective throughput near 30 rps no
  matter the configured RPS.
