# Helm Chart — voting-app

Chart para deploy da aplicação de votação (vote, redis, worker, db, result).

## Instalação

```bash
helm install voting-app ./voting-app \
  --namespace voting-app \
  --create-namespace
```

## Upgrade

```bash
helm upgrade voting-app ./voting-app --namespace voting-app
```

## Customizando por ambiente

Crie um `values-prod.yaml` só com o que muda e sobreponha o default:

```yaml
# values-prod.yaml
vote:
  replicaCount: 4
  autoscaling:
    enabled: true

result:
  replicaCount: 4
  autoscaling:
    enabled: true

postgres:
  existingSecret: voting-app-db-credentials   # criado fora do chart (Vault/ESO)
  persistence:
    size: 20Gi
    storageClassName: gp3
```

```bash
helm install voting-app ./voting-app \
  --namespace voting-app --create-namespace \
  -f values-prod.yaml
```

## Rodando no EKS

Se estiver usando o Terraform do EKS deste mesmo pacote (`terraform-eks/`), o
addon do EBS CSI Driver já é habilitado e um `StorageClass` `gp3` é criado
como default — basta usar `postgres.persistence.storageClassName: gp3` (ou
deixar em branco para usar o default do cluster, se `gp3` for o default).

## Desinstalando

```bash
helm uninstall voting-app --namespace voting-app
```

Isso remove Deployments, Services e Secrets do release, mas **não** remove o
PVC do Postgres por padrão (comportamento do Kubernetes para evitar perda
acidental de dados). Para apagar também o volume:

```bash
kubectl delete pvc -n voting-app -l app.kubernetes.io/instance=voting-app
```

## Estrutura

```
voting-app/
├── Chart.yaml
├── values.yaml
├── .helmignore
└── templates/
    ├── _helpers.tpl
    ├── redis.yaml              # Deployment + Service
    ├── postgres-secret.yaml    # Secret (condicional a existingSecret)
    ├── postgres.yaml           # Service headless + StatefulSet (volumeClaimTemplates)
    ├── vote.yaml               # Deployment + Service + HPA (opcional)
    ├── result.yaml             # Deployment + Service + HPA (opcional)
    ├── worker.yaml             # Deployment (sem Service)
    └── NOTES.txt
```

## Notas de segurança

- `postgres.auth.password` no `values.yaml` é só para dev/teste. Em produção,
  defina `postgres.existingSecret` apontando para um Secret gerenciado fora do
  chart (Vault, AWS Secrets Manager + External Secrets Operator, Sealed
  Secrets etc.) — nunca versione senha real em `values.yaml`.
- `worker.replicaCount` deve permanecer `1`: a imagem não implementa lock
  distribuído para consolidação dos votos.

## Nota sobre o Postgres (StatefulSet)

O `db` é um `StatefulSet` com `volumeClaimTemplates` (não um `Deployment` com
uma PVC solta) — é o padrão correto para cargas stateful no Kubernetes: cada
pod recebe sua própria PVC nomeada automaticamente
(`postgres-storage-<release>-voting-app-db-0`), evitando o risco de dois pods
disputando o mesmo volume `ReadWriteOnce` caso `replicas` seja alterado.

Se você já tinha instalado uma versão anterior deste chart com Postgres como
`Deployment`, o Helm não consegue migrar o recurso "no lugar" (são `kind`s
diferentes). Para atualizar:

```bash
helm uninstall voting-app --namespace voting-app
kubectl delete pvc -n voting-app -l app.kubernetes.io/instance=voting-app
helm install voting-app ./voting-app --namespace voting-app --create-namespace
```

Isso descarta os dados existentes no Postgres — tudo bem em dev/teste, mas
planeje uma migração de dados (`pg_dump`/`pg_restore`) se algum dia isso for
aplicado sobre uma base com dados reais.

## Gateway API + TLS (vote e result)

Com `gateway.enabled: true` (default), `vote` e `result` deixam de ser
`Service type: LoadBalancer` e passam a ser `ClusterIP`, expostos por trás de
um único ALB via **Gateway API** (`Gateway` + `HTTPRoute`), provisionado pelo
AWS Load Balancer Controller.

**Pré-requisitos no cluster** (ver `terraform-eks/README.md`):
- AWS Load Balancer Controller instalado (>= v2.14.0, suporte a Gateway API L7/ALB).
- CRDs padrão do Gateway API instaladas (`kubectl apply -f .../standard-install.yaml`).
- Um certificado no ACM cujos SANs batem com `gateway.voteHostname` e
  `gateway.resultHostname` (o `terraform-eks/gateway.tf` já gera e importa um
  autoassinado com esses SANs por padrão).

```bash
helm install voting-app ./voting-app \
  --namespace voting-app --create-namespace \
  --set postgres.persistence.storageClassName=gp3
```

```bash
kubectl get gateway -n voting-app voting-app-voting-app-gateway
```

**Importante**: o controller **exige um hostname no listener** para montar o
modelo do ALB — não dá para omitir e apontar só um certificado por ARN (isso
falha com `No hostnames found for TLS cert discovery`). Por isso o chart usa
`gateway.voteHostname`/`gateway.resultHostname` (hostnames "falsos", que só
precisam bater com os SANs do certificado — não precisam resolver em DNS
público) e deixa o controller **descobrir automaticamente** o certificado
certo no ACM a partir desse hostname.

Quando `ADDRESS` aparecer no `kubectl get gateway`, o acesso **não funciona**
batendo direto no IP/DNS do ALB — o roteamento é por Host/SNI. Use
`--connect-to` do curl para simular isso sem precisar de DNS real:

```bash
ALB=$(kubectl get gateway -n voting-app voting-app-voting-app-gateway -o jsonpath='{.status.addresses[0].value}')

curl -k --connect-to vote.voting-app.local:443:$ALB:443 \
  https://vote.voting-app.local/

curl -k --connect-to result.voting-app.local:8443:$ALB:8443 \
  https://result.voting-app.local:8443/
```

Para testar no navegador, resolva o ALB para um IP e adicione ao `/etc/hosts`:

```bash
dig +short $ALB
```
```
<IP-resolvido>  vote.voting-app.local
<IP-resolvido>  result.voting-app.local
```
(o ALB pode ter mais de um IP e eles podem rotacionar — ok para teste curto,
não confie nisso por muito tempo.)

**Por que portas diferentes em vez de um único host:443**: com hostnames que
não são domínios reais, não há motivo para complicar com múltiplos hosts na
mesma porta — cada serviço fica em uma porta HTTPS própria no mesmo ALB. Com
um domínio real de verdade, o padrão recomendado é usar hostnames reais
(`vote.dominio.com`, `result.dominio.com`) ambos na porta 443.

**Certificado autoassinado**: `curl -k` e o navegador vão acusar "conexão não
confiável" — esperado para autoassinado, não é um erro de configuração.

**Voltando para LoadBalancer simples**: `--set gateway.enabled=false` desliga
o Gateway e os Services de `vote`/`result` voltam a ser criados como
`LoadBalancer` (usa o valor de `vote.service.type`/`result.service.type`, que
por padrão agora é `ClusterIP` — ajuste também esses valores se desativar o
gateway).

**Aviso da própria AWS**: a documentação oficial do AWS Load Balancer
Controller marca a combinação com Gateway API como não recomendada para
produção ainda (feature GA recente). Bom para teste; reavalie antes de usar
em produção.
