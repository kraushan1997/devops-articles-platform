# Which machines Karpenter may launch. The Karpenter controller and its CRDs are
# installed in layer 1; these objects need the CRDs to exist at plan time, which is
# why they live here.

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# EKS-optimised AL2023 (chrony + Amazon Time Sync built in), private subnets,
# cluster security group, encrypted gp3 root volume, IMDSv2 only.
resource "kubernetes_manifest" "karpenter_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      role                       = "${var.eks_cluster_name}-karpenter-node" # created in layer 1
      amiSelectorTerms           = [{ alias = "al2023@latest" }]
      subnetSelectorTerms        = [{ tags = { "karpenter.sh/discovery" = var.eks_cluster_name } }]
      securityGroupSelectorTerms = [{ tags = { "karpenter.sh/discovery" = var.eks_cluster_name } }]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpTokens              = "required"
        httpPutResponseHopLimit = 1
      }
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs        = { volumeSize = "50Gi", volumeType = "gp3", encrypted = true }
      }]
    }
  }
}

# Spot first with on-demand fallback, spread over 3 AZs; consolidation removes
# empty/under-used nodes. The CPU limit caps the maximum spend.
resource "kubernetes_manifest" "karpenter_node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          expireAfter  = "720h"
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r", "t"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["4"] },
            { key = "topology.kubernetes.io/zone", operator = "In", values = slice(data.aws_availability_zones.available.names, 0, 3) },
          ]
        }
      }
      limits     = { cpu = "64" }
      disruption = { consolidationPolicy = "WhenEmptyOrUnderutilized", consolidateAfter = "2m" }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_node_class]
}
