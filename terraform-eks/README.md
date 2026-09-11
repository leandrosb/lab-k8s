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

## 5. Deploy da aplicação via Helm

Com o cluster pronto (nós `Ready`, addon do EBS CSI Driver ativo, controller
do Load Balancer rodando):

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep -E "ebs-csi|aws-load-balancer-controller"
```

O caminho padrão do chart expõe `vote` e `result` como `Service type:
LoadBalancer` (um NLB cada, TLS terminado no próprio NLB via anotações) —
**não precisa** das CRDs do Gateway API para isso, só do AWS Load Balancer
Controller já instalado pelo Terraform:

```bash
helm install voting-app ../helm/voting-app \
  --namespace voting-app --create-namespace \
  --set postgres.persistence.storageClassName=gp3 \
  --set awsLoadBalancer.certificateArn="$(terraform output -raw acm_self_signed_certificate_arn)"
```

Depois de alguns instantes:

```bash
kubectl get svc -n voting-app voting-app-voting-app-vote voting-app-voting-app-result
```

Quando o `EXTERNAL-IP` aparecer em cada um, acesse direto — `curl -k
https://<EXTERNAL-IP>/` (o certificado é autoassinado, o `-k`/aviso do
navegador é esperado).

### Opcional: Gateway API (alternativa desligada por padrão)

O chart também tem uma implementação via Gateway API (`gateway.enabled:
true`), um único ALB compartilhado em vez de 2 NLBs. Ela **exige** as CRDs
upstream do Gateway API, que não vêm com o chart do controller:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
# verifique se há uma versão mais recente em:
# https://github.com/kubernetes-sigs/gateway-api/releases

kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

Detalhes de uso em `helm/voting-app/README.md` (seção "Gateway API + TLS").
Vale reconsiderar essa via só com um domínio real disponível — a própria AWS
ainda não recomenda essa combinação para produção.

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
- **Certificado autoassinado importado no ACM**: só existe porque não há
  domínio público disponível para validação DNS. No caminho padrão (NLB), o
  chart referencia o certificado **direto pelo ARN**
  (`awsLoadBalancer.certificateArn`) — sem ambiguidade. Assim que houver um
  domínio real, troque por um certificado ACM emitido (`aws_acm_certificate`
  com `domain_name` + validação DNS via Route 53).
- **Gateway API + AWS Load Balancer Controller (alternativa opcional,
  desligada por padrão)**: a própria documentação da AWS declara que essa
  combinação *"não é recomendada para produção ainda"* (feature GA recente).
  Além disso, o controller exige um hostname no listener para montar o
  modelo do ALB (não dá para só fixar o ARN do certificado e omitir o
  hostname) — por isso essa via usa hostnames "falsos"
  (`vote.voting-app.local`, `result.voting-app.local`) que batem com os SANs
  do certificado mas não resolvem em DNS público de verdade, e cada serviço
  fica em uma porta separada (443/8443) no mesmo ALB, já que sem domínio não
  há hostname real para rotear por Host. Só vale reconsiderar com um domínio
  real disponível.

## Destruindo o ambiente

```bash
terraform destroy -var-file=terraform.tfvars
```

O bucket de state e a tabela DynamoDB (`bootstrap/`) têm
`prevent_destroy = true` e não são removidos por este comando — isso é
intencional, para não apagar o histórico de state por engano.
