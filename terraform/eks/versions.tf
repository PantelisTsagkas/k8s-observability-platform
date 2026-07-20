# versions.tf: provider + Terraform version pins, and the state backend.
#
# Why pin: an unpinned provider silently upgrades on the next `terraform init`
# and can change plan output under you. We pin to the major line we tested
# against (~> means "any 6.x, not 7.0").
#
# State backend: intentionally LOCAL (the default, so there is no `backend`
# block here). This cluster is build-and-destroy the same day, so the state is
# throwaway. Local state means nothing survives `terraform destroy` - no S3


terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # default_tags stamps every taggable resource this provider creates. That is
  # how we guarantee a clean audit + teardown: after `terraform destroy` we can
  # search the console for Project=k8s-observability-platform and confirm zero.
  default_tags {
    tags = {
      Project   = "k8s-observability-platform"
      Phase     = "3-eks"
      ManagedBy = "terraform"
    }
  }
}
