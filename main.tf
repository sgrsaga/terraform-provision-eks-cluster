provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "pipeline-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "education-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

## EKS Module

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.5.1"

  cluster_name    = local.cluster_name
  cluster_version = "1.24"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  ## Node group with 1 server for Ingress-Controller
  eks_managed_node_groups = {
    one = {
      name = "eks-ng1"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }
  }
  /*
  ## Fargate profiles for data plane
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "default"
        }
      ]
    },

    ## Ingress Controller is not supported in Fargate we need node group to deploy Ingress
    nginx-ingress = {
      name = "nginx-ingress"
      selectors = [
        {
          namespace = "ingress-nginx"
        }
      ]
    },
    argocd = {
      name = "argocdns"
      selectors = [
        {
          namespace = "argocd"
        }
      ]
    },
    kubesystem = {
      name = "kubesystem"
      selectors = [
        {
          namespace = "kube-system"
        }
      ]
    }
  }
  */
}

/*
module "fargate_profile" {
  source  = "terraform-aws-modules/eks/aws//modules/fargate-profile"
  version = "19.7.0"

  name         = "separate-fargate-profile"
  cluster_name = "my--fargate-cluster"

  subnet_ids = [module.vpc.private_subnets]
  selectors = [{
    namespace = "fargatens"
  }]

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  depends_on = [module.vpc]
}
*/



## AWS Ingress 
data "aws_region" "current" {}

data "aws_eks_cluster" "target" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "aws_iam_authenticator" {
  name = data.aws_eks_cluster.target.name
}

provider "kubernetes" {
  alias = "eks"
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.aws_iam_authenticator.token
  load_config_file       = false
}

module "alb_ingress_controller" {
  source  = "iplabs/alb-ingress-controller/kubernetes"
  version = "3.1.0"

  providers = {
    kubernetes = kubernetes.eks
  }

  k8s_cluster_type = "eks"
  k8s_namespace    = "kube-system"

  aws_region_name  = data.aws_region.current.name
  k8s_cluster_name = data.aws_eks_cluster.target.name

  depends_on = [
    module.eks
  ]
}