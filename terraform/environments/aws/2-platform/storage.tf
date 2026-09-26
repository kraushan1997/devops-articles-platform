# Encrypted gp3 as the default StorageClass (MongoDB PVCs). WaitForFirstConsumer
# creates each EBS volume in the AZ where its pod was scheduled; Retain keeps the
# data if a PVC is deleted by mistake. Lives in layer 2 because a Kubernetes
# object needs a running cluster at plan time.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Retain"
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}
