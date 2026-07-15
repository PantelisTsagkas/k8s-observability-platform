# k8s-observability-platform

**Status: ACTIVE** - Phase 1 in progress: the Helm chart is done, the
monitoring stack (kube-prometheus-stack + Loki) is next.

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
| 1 | Helm chart + kube-prometheus-stack + Loki | Chart done, stack next |
| 2 | GitOps with ArgoCD, commit-to-deployed | Not started |
| 3 | EKS with Terraform, deploy the same charts, destroy same day | Not started |

## Architecture

Unchanged by Phase 1: the chart renders down to exactly these objects.
Only how they get applied changed.

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

## Running

Prerequisites: docker, kubectl, helm, k3d (all via `brew install`).

```bash
# The port mapping is load-bearing: it maps localhost:8080 to the
# cluster's ingress controller, which is how the app is reached.
k3d cluster create obs-platform --agents 2 --port "8080:80@loadbalancer"

helm install obs-sim ./charts/obs-sim -n obs-sim --create-namespace

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

To watch the HPA scale, raise the load:

```bash
helm upgrade obs-sim ./charts/obs-sim -n obs-sim \
  --set loadgen.config.RPS=300 --set loadgen.config.CONCURRENCY=50

kubectl get hpa -n obs-sim -w
```

No `kubectl rollout restart` needed any more. The loadgen pod template
carries a `checksum/config` annotation holding a hash of the rendered
ConfigMap, so a traffic-profile change alters the pod template and the
pods roll on their own. Under Phase 0 this was a manual step, and
forgetting it made config edits look broken.

![HPA scaling from 2 to 5 replicas under load](docs/phase-0-hpa-scaling.png)

Scale-down is deliberately slower (a ~5 minute stabilization window prevents
flapping): load drops at 11m, replicas step 5 -> 4 -> 2 around 15m.

![HPA scaling back down after load drops](docs/phase-0-hpa-scaledown.png)

Teardown: `k3d cluster delete obs-platform`.

## Layout

```
apps/loadgen/     # load generator (Python, uv, tested with pytest)
charts/obs-sim/   # Phase 1: the Helm chart deployments run from
manifests/        # Phase 0: hand-written YAML, superseded by the chart,
                  # kept as the artifact it was derived from
docs/             # screenshots, decisions, EKS writeup (Phase 3)
```

## The chart

`charts/obs-sim` is hand-written rather than `helm create` scaffolding:
each template is a Phase 0 manifest with the environment-specific values
lifted into `values.yaml`, comments intact.

What `values.yaml` exposes is deliberate. The filter was "does this differ
between k3d today and EKS in Phase 3?" - image tags, replicas, resources,
the loadgen traffic profile, HPA bounds, and `ingress.className` (which is
`traefik` locally and becomes `alb` on EKS: one value, the whole point of
Phase 3). Ports, probe paths and `securityContext` stay hardcoded, because
they are properties of the app rather than deployment choices.

`manifests/` is no longer applied. It stays as a reference for what the
chart renders down to.

CI lints and renders the chart on every PR that touches it, including the
`hpa.enabled=false` and `ingress.enabled=false` paths that default values
never exercise. It also asserts the invariant the chart exists to protect:
with the HPA enabled, the obs-sim Deployment must not render a `replicas`
field, or `helm upgrade` would reset the count and fight the autoscaler.
That failure is silent in a cluster, so it is caught before merge instead.

## Lessons that cost debugging time (Phase 0)

- `runAsNonRoot: true` needs a *numeric* `USER` in the Dockerfile; the kubelet
  cannot verify a username, and fails with `CreateContainerConfigError`.
- A wrong `containerPort` broke both probes at once via the named port, and
  the liveness probe kept killing a perfectly healthy app. `kubectl describe`
  events tell the real story; `kubectl get pods` only says something is wrong.
- Env vars from a ConfigMap are read at container start. Editing the
  ConfigMap does nothing until `kubectl rollout restart`. (Phase 1 fixes
  this properly with a `checksum/config` annotation on the pod template.)
- Images built on GitHub's amd64 runners will not run on arm64 (Apple
  Silicon) nodes unless CI builds multi-arch with QEMU.
- Load generators have bottlenecks too: with 10% slow requests holding
  semaphore slots, concurrency 5 caps effective throughput near 30 rps no
  matter the configured RPS.

## Lessons that cost debugging time (Phase 1)

- Helm parse errors name where the Go template parser gave up, not where
  the mistake is. `function "ports" not defined` meant an unclosed `{{`
  on the *previous* line. `grep -n '{{' templates/*.yaml | grep -v '}}'`
  finds those in two seconds and points at the real line.
- Omitting `replicas:` from a Deployment does not mean "leave it alone".
  The API server defaults an absent `replicas` to 1. That is what you want
  when an HPA owns the count (it scales straight back to `minReplicas`),
  but it looks wrong: after install the two app pods have different ages.
- Templating `replicas` while an HPA owns it means every `helm upgrade`
  resets the count and fights the autoscaler. Render the field only when
  `hpa.enabled` is false.
- Kubernetes infers `imagePullPolicy` from the tag: `:latest` gets
  `Always`, any other tag gets `IfNotPresent`. Setting `IfNotPresent`
  explicitly on a `:latest` image means newly pushed builds are never
  pulled, and nothing anywhere reports an error.
- Never hardcode `namespace:` in a chart template. Helm sets it from `-n`.
  Hardcoding it means `helm install -n staging` records the release in one
  namespace and creates the objects in another, silently.
- `kubectl diff -f <rendered.yaml>` against the still-running Phase 0
  objects was the cheapest way to prove chart parity: four of six objects
  came back with no diff, and the two that differed were both real
  findings. Cheaper and more convincing than reading `helm template`
  output, because it compares against reality rather than intent.
