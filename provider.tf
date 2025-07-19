# main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# FIXED: Add the missing EKS cluster data source
data "aws_eks_cluster" "bsp_eks" {
  name = aws_eks_cluster.main.name
  depends_on = [aws_eks_cluster.main]
}

# EKS cluster authentication data source
data "aws_eks_cluster_auth" "bsp_eks" {
  name = aws_eks_cluster.main.name
  depends_on = [aws_eks_cluster.main]
}


# # Kubernetes provider configuration
# provider "kubernetes" {
#   host                   = aws_eks_cluster.main.endpoint
#   cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)  # Fixed typo
#   token                  = data.aws_eks_cluster_auth.bsp_eks.token
# }

# # Helm provider configuration - FIXED SYNTAX
# # ✅ CORRECT - Use a block
# provider "helm" {
#   kubernetes {
#     host                   = aws_eks_cluster.main.endpoint
#     cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
#     token                  = data.aws_eks_cluster_auth.bsp_eks.token
#   }
# }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.bsp_eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.bsp_eks.certificate_authority[0].data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", "us-east-1"]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.bsp_eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.bsp_eks.certificate_authority[0].data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", "us-east-1"]
    }
  }
}