# eks-cluster.tf
# EKS Cluster - Private Configuration
resource "aws_eks_cluster" "main" {
  name     = "bsp-eks-cluster11"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true   # API server accessible from VPC
    endpoint_public_access  = true  # Changed to true for OIDC access
    public_access_cidrs     = ["0.0.0.0/0"]
    # endpoint_public_access  = false  # API server NOT accessible from internet
    # public_access_cidrs     = []     # Empty since public access is disabled
  }

  # Enable EKS Cluster logging - All log types for better observability
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Use API-based access instead of ConfigMap (modern approach)
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = {
    Name = "bsp-eks-cluster1"
    Environment = "poc"
  }

  lifecycle {
    ignore_changes = [
      vpc_config[0].public_access_cidrs,
      vpc_config[0].endpoint_private_access,
      vpc_config[0].endpoint_public_access,
    ]
  }
}

# CloudWatch Log Group for EKS cluster logging
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/bsp-eks-cluster11/cluster"
  retention_in_days = 7

  tags = {
    Name = "bsp-eks-cluster1-logs"
  }
}


#################################################################################################################################################################

# Get supported addon versions dynamically
data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# EBS CSI Driver addon version
data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}


################################################################################################################################################3

# EKS Add-ons with dynamic versions
resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "vpc-cni"
  addon_version     = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    "enableNetworkPolicy" = "true"
  })

  depends_on = [aws_eks_cluster.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "kube-proxy"
  addon_version     = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_cluster.main]
}

# resource "aws_eks_addon" "coredns" {
#   cluster_name      = aws_eks_cluster.main.name
#   addon_name        = "coredns"
#   addon_version     = data.aws_eks_addon_version.coredns.version
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"

#   depends_on = [aws_eks_cluster.main]
# }




#########################################################################################################################################################

# EBS CSI Driver Service Account IAM Role
data "aws_iam_policy_document" "ebs_csi_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks_cluster.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver_role" {
  name               = "bsp-eks-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role_policy.json

  tags = {
    Name = "bsp-eks-ebs-csi-driver-role"
    Environment = "poc"
  }
}

# Attach the AWS managed policy for EBS CSI Driver
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"  # Fixed ARN
  role       = aws_iam_role.ebs_csi_driver_role.name
}

# EBS CSI Driver Add-on
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.ebs_csi_driver_policy,
    aws_iam_openid_connect_provider.eks_cluster
  ]

  tags = {
    Name = "bsp-eks-ebs-csi-driver"
    Environment = "poc"
  }
}



##########################################################################################################################################################

# OIDC Identity Provider (only after cluster is fully ready)

# Static thumbprint approach (no internet needed)
resource "aws_iam_openid_connect_provider" "eks_cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]  # AWS standard thumbprint
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  depends_on = [aws_eks_cluster.main]

  tags = {
    Name = "bsp-eks-cluster1-oidc-provider"
  }
}
# data "tls_certificate" "eks_cluster" {
#   url = aws_eks_cluster.main.identity[0].oidc[0].issuer

#   depends_on = [aws_eks_cluster.main]
# }

# resource "aws_iam_openid_connect_provider" "eks_cluster" {
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
#   url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

#   depends_on = [aws_eks_cluster.main]

#   tags = {
#     Name = "bsp-eks-cluster1-oidc-provider"
#   }
# }














# data "aws_eks_addon_version" "vpc-cni-default" {
#   addon_name         = "vpc-cni"
#   kubernetes_version = aws_eks_cluster.main.version
# }

# # Example: Custom VPC CNI Service Account Role
# # This provides more granular permissions and better security

# # IAM Role for VPC CNI Service Account
# resource "aws_iam_role" "vpc_cni_role" {
#   name = "bsp-eks-cluster1-vpc-cni-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = aws_iam_openid_connect_provider.eks_cluster.arn
#         }
#         Condition = {
#           StringEquals = {
#             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
#             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })

#   tags = {
#     Name = "bsp-eks-cluster1-vpc-cni-role"
#   }
# }

# # Attach the CNI policy
# resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
#   role       = aws_iam_role.vpc_cni_role.name
# }

# # Optional: Custom policy for additional permissions
# resource "aws_iam_role_policy" "vpc_cni_additional_permissions" {
#   name = "vpc-cni-additional-permissions"
#   role = aws_iam_role.vpc_cni_role.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "ec2:DescribeNetworkInterfaces",
#           "ec2:DescribeInstances",
#           "ec2:DescribeSubnets",
#           "ec2:DescribeSecurityGroups"
#         ]
#         Resource = "*"
#       }
#     ]
#   })
# }

# # VPC CNI Add-on with custom service account role
# resource "aws_eks_addon" "vpc_cni" {
#   cluster_name             = aws_eks_cluster.main.name
#   addon_name               = "vpc-cni"
# #   addon_version            = "v1.18.1-eksbuild.3"
#   addon_version     = data.aws_eks_addon_version.vpc-cni-default.version
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   service_account_role_arn = aws_iam_role.vpc_cni_role.arn  # Custom role

#   configuration_values = jsonencode({
#     "enableNetworkPolicy" = "true"
#     "env" = {
#       "ENABLE_POD_ENI" = "true"
#       "ENABLE_PREFIX_DELEGATION" = "true"
#     }
#   })

#   depends_on = [
#     aws_eks_cluster.main,
#     aws_iam_role_policy_attachment.vpc_cni_policy
#   ]
# }

# # # Comparison: VPC CNI WITHOUT custom service account role
# # resource "aws_eks_addon" "vpc_cni_default" {
# #   cluster_name      = aws_eks_cluster.main.name
# #   addon_name        = "vpc-cni"
# #   addon_version     = "v1.18.1-eksbuild.3"
# #   resolve_conflicts_on_create = "OVERWRITE"
# #   resolve_conflicts_on_update = "OVERWRITE"
# #   # No service_account_role_arn - uses node role permissions
  
# #   configuration_values = jsonencode({
# #     "enableNetworkPolicy" = "true"
# #   })

# #   depends_on = [aws_eks_cluster.main]
# # }



# ####################################################################################################################################################################

# resource "aws_eks_addon" "kube_proxy" {
#   cluster_name      = aws_eks_cluster.main.name
#   addon_name        = "kube-proxy"
#   addon_version     = "v1.31.0-eksbuild.5"  # Latest for EKS 1.31
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"

#   depends_on = [aws_eks_cluster.main]
# }

# #######################################################################################################################################################################

# resource "aws_eks_addon" "coredns" {
#   cluster_name      = aws_eks_cluster.main.name
#   addon_name        = "coredns"
#   addon_version     = "v1.11.1-eksbuild.9"  # Latest for EKS 1.31
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"

#   depends_on = [aws_eks_cluster.main]
# }


# ####################################################################################################################################################################

# # EBS CSI Driver (Required for persistent volumes in EKS 1.31)
# resource "aws_eks_addon" "ebs_csi_driver" {
#   cluster_name             = aws_eks_cluster.main.name
#   addon_name               = "aws-ebs-csi-driver"
#   addon_version            = "v1.32.0-eksbuild.1"  # Latest for EKS 1.31
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn

#   depends_on = [aws_eks_cluster.main]
# }



# # IAM Role for EBS CSI Driver
# resource "aws_iam_role" "ebs_csi_driver_role" {
#   name = "bsp-eks-cluster1-ebs-csi-driver-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = aws_iam_openid_connect_provider.eks_cluster.arn
#         }
#         Condition = {
#           StringEquals = {
#             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
#             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })

#   tags = {
#     Name = "bsp-eks-cluster1-ebs-csi-driver-role"
#   }
# }

# resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/service-role/Amazon_EBS_CSI_DriverPolicy"
#   role       = aws_iam_role.ebs_csi_driver_role.name
# }


# ####################################################################################################################################################################

# # OIDC Identity Provider - Essential for Service Account Authentication
# data "tls_certificate" "eks_cluster" {
#   url = aws_eks_cluster.main.identity[0].oidc[0].issuer
# }

# resource "aws_iam_openid_connect_provider" "eks_cluster" {
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
#   url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

#   tags = {
#     Name = "bsp-eks-cluster1-oidc-provider"
#   }
# }



# # EKS Access Entry for Admin User (API-based access)
# resource "aws_eks_access_entry" "admin" {
#   cluster_name      = aws_eks_cluster.main.name
#   principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
#   kubernetes_groups = ["system:masters"]
#   type              = "STANDARD"

#   depends_on = [aws_eks_cluster.main]
# }