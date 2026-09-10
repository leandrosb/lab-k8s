output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA do cluster, em base64"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_provider_arn" {
  description = "ARN do provedor OIDC do cluster (usado para IRSA de outras aplicações)"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (onde rodam os nós do EKS)"
  value       = module.vpc.private_subnets
}

output "configure_kubectl" {
  description = "Comando para atualizar o kubeconfig local e apontar para o cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "acm_self_signed_certificate_arn" {
  description = "ARN do certificado autoassinado importado no ACM — usar em gateway.certificateArn no Helm chart"
  value       = aws_acm_certificate.voting_app.arn
}
