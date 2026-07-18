# gitops/argocd - Phase 2 bootstrap

GitOps for this platform. ArgoCD watches this repo and reconciles the cluster to
match it. After bootstrap, the obs-sim app is deployed by committing to git, not
by running `helm` or `kubectl` by hand.

## The one manual step

ArgoCD cannot install itself with ArgoCD (chicken and egg). Installing the
controller is the single bootstrap command a human runs. Everything the
controller then manages - here, the obs-sim Application - lives in git.

```bash
# Pin the chart version so the bootstrap is reproducible, not "whatever was
# latest that day". This is the same discipline the bare kube-prometheus-stack
# install skipped in Phase 1.
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 10.1.4 \
  --values gitops/argocd/argocd-values.yaml \
  --wait
```

## Reach the UI

The server runs with `--insecure` (TLS terminates at the ingress in a real
setup; locally we port-forward plain HTTP and skip cert warnings).

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:80
# UI at http://localhost:8081, user: admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## Register the app with ArgoCD

The Application CR points ArgoCD at the Helm chart in this repo. Applying it is
part of bootstrap; after that, ArgoCD owns the app.

```bash
kubectl apply -f gitops/argocd/application.yaml
```

## What ArgoCD tracks

- **repoURL**: this repo (public, so no repo credential needed).
- **targetRevision: main**: ArgoCD reads git, not your working tree. A change is
  "deployed" only once it is on `main`. Feature branches are invisible to it.
- **path: charts/obs-sim**: the Phase 1 Helm chart, rendered by ArgoCD's own
  Helm support.
