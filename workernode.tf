# # eks-nodes.tf
# # Get the latest EKS optimized AMI for version 1.31
# data "aws_ami" "eks_worker" {
#   most_recent = true
#   owners      = ["amazon"]
  
#   filter {
#     name   = "name"
#     values = ["amazon-eks-node-1.31-v*"]  # Hardcoded EKS version 1.31
#   }
  
#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
  
#   filter {
#     name   = "architecture"
#     values = ["x86_64"]
#   }
# }

# # User data script for worker nodes
# locals {
#   userdata = base64encode(templatefile("${path.module}/userdata.sh", {
#     cluster_name        = "bsp-eks-cluster1"                    # Hardcoded cluster name
#     # cluster_endpoint    = aws_eks_cluster.main.endpoint       # Dynamic cluster endpoint
#     # cluster_ca          = aws_eks_cluster.main.certificate_authority[0].data  # Dynamic CA cert
#     bootstrap_arguments = "--container-runtime containerd --kubelet-extra-args '--max-pods=17'"  # Hardcoded bootstrap args
#   }))
# }

# # Launch Template for Worker Nodes
# resource "aws_launch_template" "eks_nodes" {
#   name_prefix   = "bsp-eks-cluster-node-"  # Hardcoded cluster name prefix
#   image_id      = data.aws_ami.eks_worker.id
#   instance_type = "t3.medium"              # Hardcoded instance type
#   key_name      = "bspnew"            # Hardcoded key pair name - UPDATE THIS!

#   vpc_security_group_ids = [aws_security_group.eks_nodes.id]

#   iam_instance_profile {
#     name = aws_iam_instance_profile.eks_node_profile.name
#   }

#   user_data = local.userdata

#   # EBS Volume Configuration
#   block_device_mappings {
#     device_name = "/dev/xvda"  # Root device for Amazon Linux 2
#     ebs {
#       volume_size           = 20     # Hardcoded 20GB volume
#       volume_type           = "gp3"  # Latest generation EBS
#       encrypted             = true   # Encryption at rest
#       delete_on_termination = true   # Clean up on instance termination
#       iops                  = 3000   # Baseline IOPS for gp3
#       throughput            = 125    # Baseline throughput for gp3
#     }
#   }

#   # Instance tags applied at launch
#   # Instance tags applied at launch (✅ Correct placement)
#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name = "bsp-eks-cluster-worker-node"
#       "kubernetes.io/cluster/bsp-eks-cluster" = "owned"  # ✅ Required for EKS
#       Environment = "poc"
#       Project     = "bsp"
#     }
#   }

#   # EC2 Instance Metadata Service v2 (IMDSv2) - Security hardening
#   metadata_options {
#     http_endpoint               = "enabled"   # Enable metadata service
#     http_tokens                 = "required"  # Require session tokens (IMDSv2)
#     http_put_response_hop_limit = 2          # Limit metadata access hops
#     instance_metadata_tags      = "enabled"  # Enable instance tags in metadata
#   }

#   depends_on = [
#     aws_eks_cluster.main,
#     aws_iam_instance_profile.eks_node_profile,
#   ]

#   tags = {
#     Name = "bsp-eks-cluster-node-template"
#   }
# }

# # Worker Node 1 - AZ1 (osdu-node-1)
# resource "aws_instance" "eks_node_1" {
#   launch_template {
#     id      = aws_launch_template.eks_nodes.id
#     version = "$Latest"
#   }

#   subnet_id = data.aws_subnet.private_az1.id

#   tags = {
#     Name = "osdu-node-1"  # Custom node name as requested
#     # "kubernetes.io/cluster/bsp-eks-cluster" = "owned"
#     Environment = "poc"
#     Project     = "bsp"
#     NodeNumber  = "1"
#     AZ          = "az1"
#   }

#   depends_on = [
#     aws_eks_cluster.main,
#     aws_eks_addon.vpc_cni,
#   ]
# }

# # Worker Node 2 - AZ2 (osdu-node-2)
# resource "aws_instance" "eks_node_2" {
#   launch_template {
#     id      = aws_launch_template.eks_nodes.id
#     version = "$Latest"
#   }

#   subnet_id = data.aws_subnet.private_az2.id

#   tags = {
#     Name = "osdu-node-2"  # Custom node name as requested
#     # "kubernetes.io/cluster/bsp-eks-cluster" = "owned"
#     Environment = "poc"
#     Project     = "bsp"
#     NodeNumber  = "2"
#     AZ          = "az2"
#   }

#   depends_on = [
#     aws_eks_cluster.main,
#     aws_eks_addon.vpc_cni,
#   ]
# }

# # Worker Node 3 - AZ1 (osdu-node-3) - Distributed across AZs for HA
# resource "aws_instance" "eks_node_3" {
#   launch_template {
#     id      = aws_launch_template.eks_nodes.id
#     version = "$Latest"
#   }

#   subnet_id = data.aws_subnet.private_az1.id

#   tags = {
#     Name = "osdu-node-3"  # Custom node name as requested
#     # "kubernetes.io/cluster/bsp-eks-cluster" = "owned"
#     Environment = "poc"
#     Project     = "bsp"
#     NodeNumber  = "3"
#     AZ          = "az1"
#   }

#   depends_on = [
#     aws_eks_cluster.main,
#     aws_eks_addon.vpc_cni,
#   ]
# }


























# Get the latest EKS optimized AMI for version 1.31
data "aws_ami" "eks_worker" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amazon-eks-node-1.31-v*"]  # Hardcoded EKS version 1.31
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# User data script for worker nodes
locals {
  userdata = base64encode(templatefile("${path.module}/userdata.sh", {
    cluster_name        = "bsp-eks-cluster1"                    # Fixed: Match cluster name
    bootstrap_arguments = "--container-runtime containerd --kubelet-extra-args '--max-pods=17'"  # Hardcoded bootstrap args
  }))
}

# Launch Template for Worker Nodes
resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "bsp-eks-cluster-node-"  # Hardcoded cluster name prefix
  image_id      = data.aws_ami.eks_worker.id
  instance_type = "t3.medium"              # Hardcoded instance type
  key_name      = "bspnew"                 # Hardcoded key pair name

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.eks_node_profile.name
  }

  user_data = local.userdata

  # EBS Volume Configuration
  block_device_mappings {
    device_name = "/dev/xvda"  # Root device for Amazon Linux 2
    ebs {
      volume_size           = 20     # Hardcoded 20GB volume
      volume_type           = "gp3"  # Latest generation EBS
      encrypted             = true   # Encryption at rest
      delete_on_termination = true   # Clean up on instance termination
      iops                  = 3000   # Baseline IOPS for gp3
      throughput            = 125    # Baseline throughput for gp3
    }
  }

  # EC2 Instance Metadata Service v2 (IMDSv2) - Security hardening
  metadata_options {
    http_endpoint               = "enabled"   # Enable metadata service
    http_tokens                 = "required"  # Require session tokens (IMDSv2)
    http_put_response_hop_limit = 2          # Limit metadata access hops
    instance_metadata_tags      = "enabled"  # Enable instance tags in metadata
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_instance_profile.eks_node_profile,
  ]

  tags = {
    Name = "bsp-eks-cluster-node-template"
  }
}

# Worker Node 1 - AZ1 (osdu-node-1)
resource "aws_instance" "eks_node_1" {
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  subnet_id = data.aws_subnet.private_az1.id

  tags = {
    Name                                     = "osdu-node-1"  # Custom node name as requested
    "kubernetes.io/cluster/bsp-eks-cluster1" = "owned"        # EKS cluster tag (FIXED)
    Environment                              = "poc"
    Project                                  = "bsp"
    NodeNumber                               = "1"
    AZ                                       = "az1"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
  ]
}

# Worker Node 2 - AZ2 (osdu-node-2)
resource "aws_instance" "eks_node_2" {
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  subnet_id = data.aws_subnet.private_az2.id

  tags = {
    Name                                     = "osdu-node-2"  # Custom node name as requested
    "kubernetes.io/cluster/bsp-eks-cluster1" = "owned"        # EKS cluster tag (FIXED)
    Environment                              = "poc"
    Project                                  = "bsp"
    NodeNumber                               = "2"
    AZ                                       = "az2"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
  ]
}

# Worker Node 3 - AZ1 (osdu-node-3) - Distributed across AZs for HA
resource "aws_instance" "eks_node_3" {
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  subnet_id = data.aws_subnet.private_az1.id

  tags = {
    Name                                     = "osdu-node-3"  # Custom node name as requested
    "kubernetes.io/cluster/bsp-eks-cluster1" = "owned"        # EKS cluster tag (FIXED)
    Environment                              = "poc"
    Project                                  = "bsp"
    NodeNumber                               = "3"
    AZ                                       = "az1"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
  ]
}