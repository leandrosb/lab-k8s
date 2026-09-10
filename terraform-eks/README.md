# Terraform — EKS para a voting-app

Provisiona um cluster EKS (VPC dedicada, node group gerenciado, addons e
EBS CSI Driver com IRSA) pronto para receber o Helm chart `voting-app`.

## Estrutura

```
terraform-eks/
├── bootstrap/                    # cria o bucket S3 + tabela DynamoDB do remote state
│   └── main.tf
├── versions.tf                   # constraints de Terraform e providers
├── backend.tf                    # backend S3 parcial (preenchido via -backend-config)
├── backend-dev.hcl.example
├── backend-prod.hcl.example
├── providers.tf                  # aws, kubernetes, helm
├── variables.tf
├── vpc.tf                        # módulo terraform-aws-modules/vpc
├── eks.tf                        # módulo terraform-aws-modules/eks + IRSA do EBS CSI
├── addons.tf                     # StorageClass gp3 default
├── outputs.tf
└── terraform.tfvars.example
```

## 1. Bootstrap do remote state (uma vez por conta/região)

```bash
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=SEU-BUCKET-terraform-state"
```

Isso cria o bucket S3 (versionado, criptografado, sem acesso público) e a
tabela DynamoDB `terraform-locks` usados pelo backend do projeto principal.

## 2. Configurar o backend do ambiente

```bash
cd ..
cp backend-dev.hcl.example backend-dev.hcl
# edite backend-dev.hcl com o nome real do bucket criado no passo 1
```

> `backend-dev.hcl` e `backend-prod.hcl` ficam fora do controle de versão
> (veja `.gitignore`) só por conterem nomes de bucket específicos do
> ambiente — não há segredo neles, mas evita divergência entre ambientes.

## 3. Init, plan e apply

```bash
terraform init -backend-config=backend-dev.hcl

cp terraform.tfvars.example terraform.tfvars
# ajuste cluster_name, node sizes, cidrs etc. conforme o ambiente

terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Para produção, repita com `backend-prod.hcl` e um `terraform.tfvars` próprio
(namespace de state e recursos completamente isolados de dev — mesma prática
de pipelines separados por ambiente).

## 4. Configurar o kubectl

```bash
terraform output -raw configure_kubectl | bash
# ou diretamente:
aws eks update-kubeconfig --region <região> --name <cluster_name>-<environment>
```

## 5. Instalar as CRDs do Gateway API (passo único por cluster)

O `terraform apply` já instalou o AWS Load Balancer Controller, mas as CRDs
padrão do Gateway API (`Gateway`, `GatewayClass`, `HTTPRoute`) não fazem
parte do chart do controller — vêm do projeto upstream:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
# verifique se há uma versão mais recente em:
# https://github.com/kubernetes-sigs/gateway-api/releases
```

Se o controller já estava rodando antes desse apply, reinicie-o para
garantir que ele detecte o suporte a Gateway API:

```bash
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
kubectl rollout status  deployment aws-load-balancer-controller -n kube-system
```

## 6. Deploy da aplicação via Helm

Com o cluster pronto (nós `Ready`, addon do EBS CSI Driver ativo, controller
do Load Balancer rodando):

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep -E "ebs-csi|aws-load-balancer-controller"

terraform output -raw acm_self_signed_certificate_arn
```

```bash
helm install voting-app ../helm/voting-app \
  --namespace voting-app --create-namespace \
  --set postgres.persistence.storageClassName=gp3 \
  --set gateway.certificateArn="<ARN do output acima>"
```

Depois de alguns minutos (provisionamento do ALB):

```bash
kubectl get gateway -n voting-app voting-app-voting-app-gateway
```

Quando o campo `ADDRESS` aparecer, acesse `https://<endereço>:443/` (vote) e
`https://<endereço>:8443/` (result). O certificado é autoassinado — o
navegador vai alertar sobre isso; é esperado (veja a nota abaixo).

## Decisões e observações importantes

- **VPC dedicada com subnets públicas/privadas**: os nós do EKS rodam nas
  subnets privadas; NAT Gateway nas públicas para saída à internet (pull de
  imagens, etc.). `single_nat_gateway = true` por padrão para reduzir custo
  em dev — mude para `false` em produção para não ter ponto único de falha.
- **EBS CSI Driver + IRSA**: obrigatório para o PVC do Postgres funcionar.
  Sem esse addon e a role IRSA associada, o PVC fica `Pending` indefinidamente.
- **`enable_cluster_creator_admin_permissions = true`**: garante que quem
  rodou o `apply` tenha acesso admin ao cluster via EKS Access Entries,
  evitando ficar bloqueado fora do cluster logo após criá-lo.
- **`cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]`** por padrão
  (facilita começar): em produção, restrinja aos IPs/VPN da equipe ou
  desative o acesso público e use um bastion/VPN dentro da VPC.
- **Remote state em S3 + DynamoDB, separado por ambiente**: cada ambiente
  tem seu próprio `key` no S3 e compartilha a mesma tabela de lock — isso
  segue a mesma prática de pipelines/estado separados por ambiente.
- **`node_capacity_type = "ON_DEMAND"`**: troque para `"SPOT"` em cargas
  tolerantes a interrupção para reduzir custo (o worker, por exemplo, não é
  um bom candidato a Spot por manter estado de fila em processamento; vote,
  result e o próprio node group misto merecem mais atenção antes de mover
  tudo para Spot).
- **Gateway API + AWS Load Balancer Controller**: a própria documentação da
  AWS declara que essa combinação *"não é recomendada para produção ainda"*
  (é uma feature relativamente nova, GA em 2026). Adequado para teste/estudo;
  reavalie antes de usar em produção.
- **Certificado autoassinado importado no ACM**: só existe porque não há
  domínio público disponível para validação DNS. O Gateway referencia o
  certificado pelo ARN diretamente (não por hostname), o que só é possível
  porque o controller suporta essa "configuração estática" de certificado.
  Navegadores vão acusar conexão não confiável — normal para autoassinado.
  Assim que houver um domínio real, troque por um certificado ACM emitido
  (`aws_acm_certificate` com `domain_name` + validação DNS via Route 53) e
  passe a usar hostnames reais nos Listeners (habilita também a descoberta
  automática de certificado por hostname, sem precisar do ARN estático).
- **Vote e result na mesma ALB, em portas diferentes**: sem hostname não dá
  para rotear por domínio, então a diferenciação é por porta (443 e 8443).
  Com um domínio real, o ideal é usar hostnames (`vote.dominio.com`,
  `result.dominio.com`) todos na porta 443 padrão.

## Destruindo o ambiente

```bash
terraform destroy -var-file=terraform.tfvars
```

O bucket de state e a tabela DynamoDB (`bootstrap/`) têm
`prevent_destroy = true` e não são removidos por este comando — isso é
intencional, para não apagar o histórico de state por engano.
