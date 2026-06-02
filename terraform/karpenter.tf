module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.31"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions           = true
  enable_pod_identity             = true
  create_pod_identity_association = true

  # Lets nodes use SSM Session Manager for debugging.
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  wait       = true

  values = [
    yamlencode({
      nodeSelector = {
        role = "system"
      }
      tolerations = [{
        key      = "CriticalAddonsOnly"
        operator = "Exists"
      }]
      serviceAccount = {
        name = "karpenter"
      }
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
    })
  ]
}

resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = templatefile("${path.module}/manifests/ec2nodeclass.yaml.tftpl", {
    cluster_name       = var.cluster_name
    node_iam_role_name = module.karpenter.node_iam_role_name
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "nodepool_amd64" {
  yaml_body = file("${path.module}/manifests/nodepool-amd64.yaml")

  depends_on = [kubectl_manifest.ec2nodeclass]
}

resource "kubectl_manifest" "nodepool_arm64" {
  yaml_body = file("${path.module}/manifests/nodepool-arm64.yaml")

  depends_on = [kubectl_manifest.ec2nodeclass]
}
