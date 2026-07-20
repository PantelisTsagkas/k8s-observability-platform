# eks.tf: the cluster itself + one managed node group.
#
# terraform-aws-modules/eks hides a LOT of correct-but-tedious wiring: the
# control-plane IAM role, security groups, the OIDC provider that makes IRSA
# possible, node IAM roles, and access entries. We comment on WHAT it sets up
# rather than reproducing it by hand.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Put the control-plane ENIs and the nodes in the PRIVATE subnets. Nodes have
  # no public IPs; they reach the internet through the single NAT gateway.
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public API endpoint so we can run kubectl from the laptop. For a real
  # long-lived cluster you would lock this down with endpoint_public_access_cidrs
  # or go private-only + a bastion. Fine for a short-lived learning cluster.
  endpoint_public_access = true

  # OIDC provider on = IRSA works. This is the mechanism that lets a specific
  # Kubernetes ServiceAccount assume a specific IAM role (see irsa.tf). It is
  # THE reason we can give the LB controller pod AWS permissions without putting
  # credentials on the node.
  enable_irsa = true

  # authentication_mode = "API" uses EKS Access Entries (the modern way) instead
  # of the legacy aws-auth ConfigMap. enable_cluster_creator_admin_permissions
  # then grants the IAM identity running `terraform apply` (you) cluster-admin
  # via an access entry. Without this you create the cluster and immediately get
  # "error: You must be logged in to the server (Unauthorized)" on the first
  # kubectl - the classic first-EKS lockout.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # Core add-ons managed by EKS (kept at the versions the module knows are
  # compatible with the control-plane version). vpc-cni gives pods VPC IPs,
  # coredns is in-cluster DNS, kube-proxy wires up Service networking.
  # NOTE: metrics-server is NOT here - it is not an automatic EKS component, so
  # the HPA has no metrics until we install it in the runbook.
  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  # One managed node group on SPOT. Spot is ~70% cheaper and totally fine for a
  # cluster we will destroy in an hour; the tradeoff (possible interruption) does
  # not matter here. Managed = EKS handles the AMI, bootstrap, and draining.
  eks_managed_node_groups = {
    default = {
      instance_types = [var.instance_type]
      capacity_type  = "SPOT"

      min_size     = var.desired_size
      max_size     = var.desired_size + 2 # small ceiling so a runaway HPA can't scale the bill
      desired_size = var.desired_size
    }
  }
}
