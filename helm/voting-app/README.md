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
    ├── postgres-pvc.yaml       # PVC (condicional a persistence.enabled)
    ├── postgres.yaml           # Deployment + Service
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
