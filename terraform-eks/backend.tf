# Backend parcial: blocos "backend" não aceitam variáveis, então os valores
# reais vêm de um arquivo -backend-config por ambiente (veja backend-dev.hcl
# e backend-prod.hcl), mantendo state e locking separados por ambiente:
#
#   terraform init -backend-config=backend-dev.hcl
#   terraform init -backend-config=backend-prod.hcl
#
terraform {
  backend "s3" {
    encrypt = true
  }
}
