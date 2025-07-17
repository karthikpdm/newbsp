# eks-cluster.tf
# EKS Cluster - Private Configuration
resource "aws_eks_cluster" "main" {
  name     = "bsp-eks-cluster1"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true   # API server accessible from VPC
    endpoint_public_access  = false  # API server NOT accessible from internet
    public_access_cidrs     = []     # Empty since public access is disabled
  }

  # Enable EKS Cluster logging - All log types for better observability
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Use API-based access instead of ConfigMap (modern approach)
  access_config {
    authentication_mode = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = {
    Name = "bsp-eks-cluster"
    Environment = "poc"
  }
}

# CloudWatch Log Group for EKS cluster logging
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/bsp-eks-cluster/cluster"
  retention_in_days = 7

  tags = {
    Name = "bsp-eks-cluster-logs"
  }
}


#################################################################################################################################################################



data "aws_eks_addon_version" "vpc-cni-default" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
}

# Example: Custom VPC CNI Service Account Role
# This provides more granular permissions and better security

# IAM Role for VPC CNI Service Account
resource "aws_iam_role" "vpc_cni_role" {
  name = "bsp-eks-cluster-vpc-cni-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_cluster.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "bsp-eks-cluster-vpc-cni-role"
  }
}

# Attach the CNI policy
resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_role.name
}

# Optional: Custom policy for additional permissions
resource "aws_iam_role_policy" "vpc_cni_additional_permissions" {
  name = "vpc-cni-additional-permissions"
  role = aws_iam_role.vpc_cni_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# VPC CNI Add-on with custom service account role
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
#   addon_version            = "v1.18.1-eksbuild.3"
  addon_version     = data.aws_eks_addon_version.vpc-cni-default.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = aws_iam_role.vpc_cni_role.arn  # Custom role

  configuration_values = jsonencode({
    "enableNetworkPolicy" = "true"
    "env" = {
      "ENABLE_POD_ENI" = "true"
      "ENABLE_PREFIX_DELEGATION" = "true"
    }
  })

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.vpc_cni_policy
  ]
}

# # Comparison: VPC CNI WITHOUT custom service account role
# resource "aws_eks_addon" "vpc_cni_default" {
#   cluster_name      = aws_eks_cluster.main.name
#   addon_name        = "vpc-cni"
#   addon_version     = "v1.18.1-eksbuild.3"
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   # No service_account_role_arn - uses node role permissions
  
#   configuration_values = jsonencode({
#     "enableNetworkPolicy" = "true"
#   })

#   depends_on = [aws_eks_cluster.main]
# }


####################################################################################################################################################################

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "kube-proxy"
  addon_version     = "v1.31.0-eksbuild.5"  # Latest for EKS 1.31
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_cluster.main]
}

#######################################################################################################################################################################

resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "coredns"
  addon_version     = "v1.11.1-eksbuild.9"  # Latest for EKS 1.31
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_cluster.main]
}


####################################################################################################################################################################

# EBS CSI Driver (Required for persistent volumes in EKS 1.31)
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.32.0-eksbuild.1"  # Latest for EKS 1.31
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn

  depends_on = [aws_eks_cluster.main]
}



# IAM Role for EBS CSI Driver
resource "aws_iam_role" "ebs_csi_driver_role" {
  name = "bsp-eks-cluster-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_cluster.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "bsp-eks-cluster-ebs-csi-driver-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/Amazon_EBS_CSI_DriverPolicy"
  role       = aws_iam_role.ebs_csi_driver_role.name
}


####################################################################################################################################################################

# OIDC Identity Provider - Essential for Service Account Authentication
data "tls_certificate" "eks_cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "bsp-eks-cluster-oidc-provider"
  }
}



# EKS Access Entry for Admin User (API-based access)
resource "aws_eks_access_entry" "admin" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  kubernetes_groups = ["system:masters"]
  type              = "STANDARD"

  depends_on = [aws_eks_cluster.main]
}