module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        # CoreDNS has to tolerate the system taint and prefer the system node group.
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }]
        nodeSelector = {
          role = "system"
        }
      })
    }
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        role = "system"
      }

      taints = {
        critical = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Karpenter discovers the cluster security group by this tag.
  node_security_group_tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })

  tags = var.tags
}
