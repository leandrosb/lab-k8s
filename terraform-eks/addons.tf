# StorageClass gp3 como default do cluster — usada pelo PVC do Postgres no
# chart Helm (postgres.persistence.storageClassName: gp3, ou em branco se
# esta for de fato a default do cluster).
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [module.eks]
}

# NOTA: clusters EKS mais antigos podem já ter uma StorageClass "gp2" marcada
# como default (via provisionador in-tree). Nesse caso, o Kubernetes aceita
# duas classes "default" sem erro, mas o comportamento de qual é usada em
# PVCs sem storageClassName explícito fica ambíguo. Se isso ocorrer, remova a
# marcação manualmente:
#   kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class-
