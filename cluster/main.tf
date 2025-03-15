# Estimate: https://calculator.aws/#/estimate?id=5ddfe1242a3cf9b17a57f0a0123f25b1becbf53b

## THIS TO AUTHENTICATE TO ECR, DON'T CHANGE IT
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    # token                  = data.aws_eks_cluster_auth.this.token
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }      
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name            = var.cluster_name
  cluster_version = "1.31"
  region          = "us-east-1"
  node_group_name = var.nodegroup_name

  node_iam_role_name = module.eks_blueprints_addons.karpenter.node_iam_role_name

  vpc_name = var.vpc_name

  vpc_cidr = "10.0.0.0/16"
  # NOTE: You might need to change this less number of AZs depending on the region you're deploying to
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    blueprint = local.name
  }
}

resource "aws_iam_role" "irsa_crossplane" {
  name = "irsa-crossplane-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:resources-system:provider-aws-*"
          }
        }
      }
    ]
  })
  tags = {
    "kubernetes.io/cluster/${local.name}" = "owned"
    "karpenter.sh/discovery"                        = local.name
  }
  depends_on = [ module.eks ]
}

resource "aws_iam_role_policy" "karpenter_ebs_policy" {
  name   = "karpenter-ebs-policy"
  role   = module.eks_blueprints_addons.karpenter.node_iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:DescribeVolumeAttribute",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        Resource = "*"
      }
    ]
  })
  depends_on = [module.eks_blueprints_addons]
}

################################################################################
# Cluster
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.23.0"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  cluster_addons = {
    kube-proxy          = { most_recent = true }
    coredns             = { most_recent = true }
    # pod_identity_agent  = { most_recent = true }

    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  eks_managed_node_group_defaults = {
    # ami_type = "BOTTLEROCKET_x86_64"
    ami_type = "AL2_ARM_64"
  }  

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_cloudwatch_log_group              = false
  create_cluster_security_group            = false
  create_node_security_group               = false
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    tostring(local.node_group_name) = {
      node_group_name = local.node_group_name
      use_name_prefix = false
      instance_types  = ["t4g.large"]

      # capacity_type  = "ON_DEMAND"
      capacity_type  = "SPOT"

      create_security_group = false

      subnet_ids   = module.vpc.private_subnets
      max_size     = 6
      desired_size = 2
      min_size     = 1

      # Launch template configuration
      create_launch_template = true              # false will use the default launch template
      launch_template_os     = "amazonlinux2eks" # amazonlinux2eks or bottlerocket

      # labels = {
      #   intent = "control-apps"
      # }
    tags = merge(local.tags, {
      "karpenter.sh/discovery" = local.name
    })      
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.16.3"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  create_delay_dependencies = [for prof in module.eks.eks_managed_node_groups : prof.node_group_arn]

  enable_aws_load_balancer_controller = false
  enable_metrics_server               = false

  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    # aws-s3-csi-driver = {
    #   service_account_role_arn = module.s3_csi_driver_irsa.iam_role_arn
    # }
  }

  # TODO: Enable this whenever needed
  enable_external_dns = true

  external_dns = {
    #chart_version = "5.0.0"
    chart_version = "1.15.0"
    repository    = "https://kubernetes-sigs.github.io/external-dns"
    namespace     = "control-plane-system"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  enable_aws_for_fluentbit = false
  aws_for_fluentbit = {
    set = [
      {
        name  = "cloudWatchLogs.region"
        value = var.region
      }
    ]
  }

  enable_karpenter = true
  karpenter_sqs = true

  karpenter = {
    chart_version       = "1.0.6"
    # repository          = "oci://public.ecr.aws/karpenter"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    namespace           = "control-plane-system"
  }
  karpenter_enable_spot_termination          = true
  karpenter_enable_instance_profile_creation = true
  karpenter_node = {
    iam_role_use_name_prefix = false
  }

  tags = local.tags
}

#   module "s3_csi_driver_irsa" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   version = "5.44.0"

#   role_name_prefix = "${module.eks.cluster_name}-s3-csi-driver-"

#   attach_policy_statements = true
#   policy_statements = {
#     s3_csi = {
#       sid = "S3CSIDriverPolicy"
#       actions = [
#         "s3:*"
#       ]
#       resources = ["*"]
#     }
#   }

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:s3-csi-driver-sa"]
#     }
#   }

#   tags = local.tags
# }

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.44.0"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "aws-auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
  ]
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.12.1"

  name = local.vpc_name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = ["10.0.32.0/19", "10.0.64.0/19", "10.0.96.0/19"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/elb"              = 1
    "karpenter.sh/discovery"              = local.name
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "owned"
    "kubernetes.io/role/internal-elb"     = 1
    "karpenter.sh/discovery"              = local.name
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = local.name
  addon_name   = "eks-pod-identity-agent"
  addon_version = "v1.3.4-eksbuild.1"
  depends_on = [ module.eks ]
}

resource "helm_release" "aws_efs_csi_driver" {
  name       = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart      = "aws-efs-csi-driver"
  namespace  = "kube-system"

  set {
    name  = "image.repository"
    value = "public.ecr.aws/efs-csi-driver/amazon/aws-efs-csi-driver"
  }

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.efs_csi_irsa_role.iam_role_arn
  }
}

module "efs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "efs-csi-driver"
  attach_efs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}


// Configure the S3 bucket as the backend for Terraform
terraform {
  backend "s3" {
    bucket = "eks-cluster-baseline-state-us"
    key    = "eks-cluster-baseline/terraform.tfstate"
    region = "us-east-1"
  }
}