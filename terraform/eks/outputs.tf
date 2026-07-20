# outputs.tf: the handful of values the runbook needs after `apply`.
# These feed the manual helm installs, so they surface exactly what those
# commands require and nothing more.

output "region" {
  description = "Region the cluster is in."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "VPC id - needed as a helm value for the LB controller."
  value       = module.vpc.vpc_id
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN to annotate the LB controller's ServiceAccount with."
  value       = module.lb_controller_irsa.arn
}
