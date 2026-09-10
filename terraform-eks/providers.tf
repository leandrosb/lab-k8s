provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# Autenticação via "exec": busca um token novo no momento exato de cada
# chamada à API do cluster (em vez de um token fixo obtido uma única vez no
# início do apply). O token de data.aws_eks_cluster_auth expira em 15 minutos
# e o apply completo (VPC + EKS + node group + addons) costuma levar mais que
# isso, causando "Unauthorized" nos últimos recursos (ex.: StorageClass).
# Requer o AWS CLI instalado e autenticado na máquina que roda o terraform.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
