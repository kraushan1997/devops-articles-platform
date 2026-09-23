# Cluster add-ons that must exist before workloads: storage class, ingress
# (AWS Load Balancer Controller) and node autoscaling (Karpenter).

# ------------------------------------------------------------------ storage
# Encrypted gp3 as the default StorageClass (MongoDB PVCs). WaitForFirstConsumer
# creates each EBS volume in the AZ where its pod is scheduled.
resource "kubectl_manifest" "gp3_storage_class" {
  yaml_body = <<-YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: gp3
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
    provisioner: ebs.csi.aws.com
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
    reclaimPolicy: Retain
    parameters:
      type: gp3
      encrypted: "true"
  YAML
}

# ------------------------------------------------------------------ ingress
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version

  values = [yamlencode({
    clusterName  = module.eks.cluster_name
    region       = var.region
    vpcId        = module.eks.vpc_id
    replicaCount = 2
    serviceAccount = {
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = module.eks.lb_controller_role_arn }
    }
    podDisruptionBudget = { maxUnavailable = 1 }
  })]
}

# ------------------------------------------------------------------ Karpenter
# ECR Public (Karpenter chart registry) only issues tokens in us-east-1
data "aws_ecrpublic_authorization_token" "token" {
  region = "us-east-1"
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = "kube-system"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = var.karpenter_chart_version
  wait                = true

  values = [yamlencode({
    serviceAccount = { name = module.eks.karpenter_service_account }
    replicas       = 2
    # run on the static system nodes, never on nodes Karpenter itself manages
    nodeSelector = { "node-role" = "system" }
    # resolve via the node's resolver so Karpenter never depends on CoreDNS pods
    dnsPolicy = "Default"
    settings = {
      clusterName       = module.eks.cluster_name
      clusterEndpoint   = module.eks.cluster_endpoint
      interruptionQueue = module.eks.karpenter_queue_name
      enableZonalShift  = true
    }
  })]
}

# Which machines Karpenter may launch: AL2023 (EKS-managed image, chrony with
# Amazon Time Sync built in), private subnets, encrypted gp3 root volume, IMDSv2.
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: ${module.eks.karpenter_node_role_name}
      amiSelectorTerms:
        - alias: al2023@latest
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      metadataOptions:
        httpEndpoint: enabled
        httpTokens: required
        httpPutResponseHopLimit: 1
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            encrypted: true
  YAML

  depends_on = [helm_release.karpenter]
}

# Spot-first with on-demand fallback, spread over 3 AZs; consolidation removes
# under-used nodes. The cpu limit caps the maximum spend.
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          expireAfter: 720h
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r", "t"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["4"]
            - key: topology.kubernetes.io/zone
              operator: In
              values: ${jsonencode(slice(data.aws_availability_zones.available.names, 0, 3))}
      limits:
        cpu: "64"
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 2m
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
