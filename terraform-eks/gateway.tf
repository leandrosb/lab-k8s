# =============================================================================
# Certificado autoassinado, importado no ACM.
#
# Sem um domínio público não é possível emitir um certificado ACM validado
# por DNS. A alternativa é gerar um certificado autoassinado e IMPORTÁ-LO no
# ACM (aws_acm_certificate sem domain_name, com private_key + certificate_body
# — modo "import", que não exige validação). O Gateway (Helm chart) referencia
# esse certificado pelo ARN diretamente, não por hostname.
#
# Navegadores vão acusar "conexão não confiável" ao acessar — esperado para
# um certificado autoassinado. Adequado só para teste; substitua por um
# certificado ACM emitido via domínio real antes de qualquer uso produtivo.
# =============================================================================
resource "tls_private_key" "voting_app" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "voting_app" {
  private_key_pem = tls_private_key.voting_app.private_key_pem

  subject {
    common_name  = "voting-app.local"
    organization = "voting-app-test"
  }

  dns_names = [
    "voting-app.local",
    "vote.voting-app.local",
    "result.voting-app.local",
  ]

  validity_period_hours = 8760 # 1 ano

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "voting_app" {
  private_key      = tls_private_key.voting_app.private_key_pem
  certificate_body = tls_self_signed_cert.voting_app.cert_pem

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# AWS Load Balancer Controller — reconcilia Ingress e Gateway API
# (Gateway/HTTPRoute) provisionando ALB/NLB automaticamente.
#
# Requer >= v2.14.0 do controller para suporte a Gateway API L7 (ALB).
# As CRDs padrão do Gateway API (Gateway, GatewayClass, HTTPRoute) NÃO vêm
# com este chart — são instaladas à parte (ver README, passo único por
# cluster). As CRDs específicas da AWS (LoadBalancerConfiguration,
# TargetGroupConfiguration, TargetGroupBinding etc.) vêm embutidas no chart e
# são aplicadas automaticamente no primeiro `helm install`.
# =============================================================================
module "lbc_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                              = "${var.cluster_name}-${var.environment}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  # Não fixei "version" de propósito: a numeração do chart não corresponde
  # 1:1 à versão do app (controller). Antes do apply, confirme uma versão de
  # chart cujo app seja >= 2.14.0:
  #   helm repo add eks https://aws.github.io/eks-charts
  #   helm repo update
  #   helm search repo eks/aws-load-balancer-controller --versions
  # e descomente a linha abaixo com o valor encontrado.
  # version = "1.xx.x"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lbc_irsa_role.iam_role_arn
  }

  depends_on = [module.eks]
}
