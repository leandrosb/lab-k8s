module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.cluster_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags exigidas pelo EKS/ELB para descoberta automática de subnets ao criar
  # LoadBalancers (Service type=LoadBalancer, Ingress com AWS LB Controller).
  public_subnet_tags = {
    "kubernetes.io/role/elb"                                          = "1"
    "kubernetes.io/cluster/${var.cluster_name}-${var.environment}"     = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                                 = "1"
    "kubernetes.io/cluster/${var.cluster_name}-${var.environment}"     = "shared"
  }

  tags = var.tags
}
