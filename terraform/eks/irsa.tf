# irsa.tf: the IAM role the AWS Load Balancer Controller pod will assume.
#
# This is the AWS-side half of IRSA. It creates:
#   - an IAM role whose trust policy says "the ServiceAccount named
#     aws-load-balancer-controller in the kube-system namespace, on THIS
#     cluster's OIDC provider, may assume me"
#   - and attaches AWS's official LB-controller permission policy to it.
#
# The Kubernetes-side half (annotating that ServiceAccount with this role's ARN)
# happens in the runbook when we `helm install` the controller. Terraform does
# not touch the cluster - that keeps `terraform destroy` from needing cluster
# auth, which is what makes teardown reliable.

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-alb-controller"

  # This flag attaches the maintained AWS Load Balancer Controller IAM policy.
  # Hand-maintaining that JSON (it's ~200 lines and changes with releases) is a
  # known footgun; letting the module own it is the point of using it.
  attach_load_balancer_controller_policy = true

  # Bind the role to exactly one ServiceAccount identity. The namespace:name
  # here MUST match what we pass to the controller's helm install, or the pod's
  # token won't satisfy the trust policy and it'll fail to talk to AWS.
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
