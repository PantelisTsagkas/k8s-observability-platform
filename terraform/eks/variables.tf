# variables.tf: the knobs. Everything here is either environment-specific or
# a thing we might reasonably want to change without editing resource blocks.
# No hardcoded region or account ID anywhere in this stack (repo rule).

variable "region" {
  description = "AWS region to build the cluster in. Defaults to the region already configured in the AWS CLI profile (eu-north-1, Stockholm)."
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Also used as a prefix for the VPC and IAM roles so everything is greppable together."
  type        = string
  default     = "obs-platform"
}

variable "kubernetes_version" {
  description = "EKS control-plane Kubernetes minor version. EKS lags upstream; pick a version AWS currently supports."
  type        = string
  default     = "1.33"
}

variable "instance_type" {
  description = "EC2 instance type for the managed node group. t3.medium (2 vCPU / 4 GiB) has enough headroom for the system pods + LB controller + app without eviction surprises on a first run. Bumpable if we add the monitoring stack."
  type        = string
  default     = "t3.medium"
}

variable "desired_size" {
  description = "Number of worker nodes to run. Two gives the HPA somewhere to spread replicas and survives one node going away."
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. /16 is plenty and leaves room for the /24 subnets below."
  type        = string
  default     = "10.0.0.0/16"
}
