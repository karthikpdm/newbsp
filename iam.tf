# File: iam-roles.tf - Fixed version
# EKS Cluster Service Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "bsp-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "bsp-eks-cluster-role"
  }
}

# Attach AWS managed policy for EKS cluster
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Node Service Role
resource "aws_iam_role" "eks_node_role" {
  name = "bsp-eks-node-role1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "bsp-eks-node-role"
  }
}

# Attach AWS managed policies for EKS nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

# SSM permissions for EKS nodes
resource "aws_iam_role_policy_attachment" "eks_ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# Instance Profile for EC2 nodes
resource "aws_iam_instance_profile" "eks_node_profile" {
  name = "bsp-eks-node-profile1"
  role = aws_iam_role.eks_node_role.name

  tags = {
    Name = "bsp-eks-node-profile"
  }
}

# Additional IAM policy for node-specific permissions
resource "aws_iam_role_policy" "eks_node_additional_policy" {
  name = "bsp-eks-node-additional-policy"
  role = aws_iam_role.eks_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}




# EKS Access Entry for Node Role (REQUIRED for API-based access)
resource "aws_eks_access_entry" "node_role" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.eks_node_role.arn
  type          = "EC2_LINUX"  # For EC2 worker nodes

  depends_on = [aws_eks_cluster.main]

  tags = {
    Name = "bsp-eks-cluster-node-access"
  }
}