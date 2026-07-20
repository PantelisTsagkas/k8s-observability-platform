# vpc.tf: the network EKS lives in.
#
# We use the community terraform-aws-modules/vpc module rather than hand-rolling
# aws_vpc + subnets + route tables + NAT + IGW (that is ~150 lines of plumbing).
# The module gives us a standard "public + private subnets across N AZs" layout.
#
# Shape we want:
#   - 2 AZs (EKS requires >= 2; 2 is cheaper than 3 and enough to learn on)
#   - private subnets  -> worker nodes live here (no public IPs, safer)
#   - public subnets   -> the internet-facing ALB gets placed here
#   - ONE NAT gateway  -> lets private nodes pull images / reach AWS APIs
#
# The NAT decision is the one cost knob that matters. The module DEFAULT is one
# NAT per AZ (here that would be 2, and in a 3-AZ setup 3). We force
# single_nat_gateway = true: one NAT shared by all private subnets. For a
# same-day cluster the saving is pennies, but the real point is never shipping
# the 3-NAT default by reflex.

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # Take the first two AZs the account has in this region.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Non-overlapping /24s carved out of the /16 above.
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # <- the cost guard rail. One NAT, not one per AZ.

  # DNS support is required for EKS (nodes resolve the API server by name, and
  # in-cluster service discovery relies on it).
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet tags are how the AWS Load Balancer Controller AUTO-DISCOVERS where to
  # put load balancers. Without these an ALB ingress fails with "no subnets
  # found". This is pure EKS tribal knowledge:
  #   role/elb          -> "put internet-facing load balancers here" (public)
  #   role/internal-elb -> "put internal load balancers here"        (private)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
