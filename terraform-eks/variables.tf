variable "aws_region" {
  description = "Região AWS onde o cluster será criado"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Nome do ambiente (dev, staging, prod) — usado em tags e nomes de recursos"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Nome base do cluster EKS (o ambiente é anexado, ex.: voting-app-dev)"
  type        = string
  default     = "voting-app"
}

variable "cluster_version" {
  description = "Versão do Kubernetes no EKS"
  type        = string
  # 1.30 saiu de suporte (extended support terminou em 2026). Antes de aplicar,
  # confirme as versões atualmente suportadas com:
  #   aws eks describe-cluster-versions --query 'clusterVersions[*].[clusterVersion,status,endOfStandardSupportDate]' --output table
  default = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones utilizadas"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (nós do EKS e workloads)"
  type        = list(string)
  default     = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (NAT Gateway, LoadBalancers)"
  type        = list(string)
  default     = ["10.0.96.0/20", "10.0.112.0/20", "10.0.128.0/20"]
}

variable "single_nat_gateway" {
  description = "true = 1 NAT Gateway (mais barato, ponto único de falha); false = 1 por AZ (mais resiliente e mais caro)"
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "Tipos de instância do node group gerenciado"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "cluster_endpoint_public_access" {
  description = "Expor o endpoint da API do cluster publicamente. Em produção, prefira false + acesso via VPN/bastion, ou restrinja com cluster_endpoint_public_access_cidrs"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público da API (se habilitado)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default = {
    Project   = "voting-app"
    ManagedBy = "terraform"
  }
}
