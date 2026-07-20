# Phase 3 EKS runbook: the money session

The infra in `terraform/eks/` is written and `terraform validate`-clean. This is
the ordered checklist for the paid part: build, deploy the identical chart,
screenshot, tear down. **Do not `terraform apply` unless you can stay ~1 hour to
`terraform destroy`.** The single biggest budget risk is walking away with the
cluster (and an orphaned ALB) still running.

Cost frame: EKS control plane ~$0.10/hr, 2x t3.medium spot + 1 NAT + 1 ALB is a
few more cents/hr. A one-hour session is well under £1. The threats are (1)
forgetting to destroy and (2) an ALB surviving destroy - both handled below.

## 0. Auth

```bash
aws login                 # session was expired
aws sts get-caller-identity   # confirm who you are before spending money
```

## 1. Preview (free)

```bash
cd terraform/eks
terraform plan            # read-only; sanity-check the resource count (~50-60)
```

## 2. Build the cluster (~15 min)

```bash
terraform apply           # type yes after reading the plan
terraform output          # note configure_kubectl, vpc_id, lb_controller_role_arn
$(terraform output -raw configure_kubectl)   # writes kubeconfig
kubectl get nodes         # expect 2 Ready nodes
```

## 3. metrics-server (HPA needs it - EKS has none by default)

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system
kubectl top nodes         # works once metrics-server is up (~30s)
```

## 4. AWS Load Balancer Controller (turns the `alb` ingress into a real ALB)

```bash
CLUSTER=$(terraform output -raw cluster_name)
VPC=$(terraform output -raw vpc_id)
ROLE_ARN=$(terraform output -raw lb_controller_role_arn)

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN \
  --set region=$(terraform output -raw region) \
  --set vpcId=$VPC

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```

The SA name + namespace here MUST match `irsa.tf` (`kube-system:aws-load-balancer-controller`).

## 5. Deploy the identical chart (the punchline)

Same chart templates from Phase 1/2, no edits. What differs on EKS lives in one
overlay, `charts/obs-sim/values-eks.yaml`: serviceMonitor off, ingress class
`alb`, and the three ALB annotations that make the ingress a *public,
ClusterIP-compatible, health-checked* load balancer (an ALB is not a drop-in for
traefik - see that file's comments).

```bash
helm upgrade --install obs-sim charts/obs-sim \
  -n obs-sim --create-namespace \
  -f charts/obs-sim/values-eks.yaml

kubectl -n obs-sim get pods,ingress
# wait for the ingress ADDRESS to become an *.elb.amazonaws.com hostname (~2-3min)
```

## 6. Verify + screenshot (do this BEFORE destroying)

```bash
ADDR=$(kubectl -n obs-sim get ingress obs-sim -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$ADDR/health
curl -s http://$ADDR/metrics | head
kubectl -n obs-sim get hpa    # target should read a % not <unknown> (metrics-server working)
```

Screenshots for `docs/`:
- `kubectl get nodes` + the AWS console EKS page (proves it's real EKS)
- app reachable via the ALB hostname
- HPA showing a live CPU target
Write these into `docs/eks-writeup.md` before teardown.

## 7. TEARDOWN - order matters (this is the budget guard)

The LB controller created an ALB that Terraform does NOT know about. Delete the
ingress FIRST so the controller removes the ALB, otherwise `terraform destroy`
hangs on ENIs still attached to the VPC, or leaves the ALB silently billing.

Deleting the ingress tells the controller to delete the ALB, but that is
**async** and the ingress carries a finalizer the controller only clears once
the ALB is actually gone. So the controller must stay alive until then - kill it
too early and the ALB orphans while the ingress hangs in `Terminating`.

```bash
# 1. remove the app. This deletes the ingress; the controller starts tearing
#    down the ALB and will clear the ingress finalizer when it's done.
helm uninstall obs-sim -n obs-sim

# 2. poll until the ingress is GONE (not just Terminating). Empty output =
#    finalizer cleared = ALB deleted. The controller did its job.
kubectl get ingress -n obs-sim
# (repeat until it returns "No resources found")

# 3. double-check no ALB remains, then it's safe to remove the controller.
aws elbv2 describe-load-balancers --region $(terraform output -raw region) \
  --query 'LoadBalancers[].LoadBalancerName' --output text   # must be empty
helm uninstall aws-load-balancer-controller -n kube-system

# 4. now destroy the infra
terraform destroy

# 5. prove zero
terraform state list      # expect empty
```

Final check in the console: search tag `Project=k8s-observability-platform`
across VPC/EC2/EKS/ELB - nothing should remain. NAT gateways and Elastic IPs are
the usual stragglers; confirm they're gone.
