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
#     cluster_name        = "bsp-eks-cluster11"                    # Hardcoded cluster name
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
    cluster_name        = "bsp-eks-cluster11"                    # Fixed: Match cluster name
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
    instance_metadata_tags      = "disabled"  # Enable instance tags in metadata
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_instance_profile.eks_node_profile,
  ]

  tags = {
    Name = "bsp-eks-cluster-node-template"
  }
}

# # Worker Node 1 - AZ1 (osdu-node-1)
# resource "aws_instance" "eks_node_1" {
#   launch_template {
#     id      = aws_launch_template.eks_nodes.id
#     version = "$Latest"
#   }

#   subnet_id = data.aws_subnet.private_az1.id

#   tags = {
#     Name                                     = "osdu-node-1"  # Custom node name as requested
#     "kubernetes.io/cluster/bsp-eks-cluster11" = "owned"        # EKS cluster tag (FIXED)
#     Environment                              = "poc"
#     Project                                  = "bsp"
#     NodeNumber                               = "1"
#     AZ                                       = "az1"
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
#     Name                                     = "osdu-node-2"  # Custom node name as requested
#     "kubernetes.io/cluster/bsp-eks-cluster11" = "owned"        # EKS cluster tag (FIXED)
#     Environment                              = "poc"
#     Project                                  = "bsp"
#     NodeNumber                               = "2"
#     AZ                                       = "az2"
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
#     Name                                     = "osdu-node-3"  # Custom node name as requested
#     "kubernetes.io/cluster/bsp-eks-cluster11" = "owned"        # EKS cluster tag (FIXED)
#     Environment                              = "poc"
#     Project                                  = "bsp"
#     NodeNumber                               = "3"
#     AZ                                       = "az1"
#   }

#   depends_on = [
#     aws_eks_cluster.main,
#     aws_eks_addon.vpc_cni,
#   ]
# }





# Worker Node 1 - osdu-istio-keycloak (AZ1)
resource "aws_instance" "eks_node_istio_keycloak" {
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  subnet_id = data.aws_subnet.private_az1.id

  tags = {
    Name                                     = "osdu-istio-keycloak"
    "kubernetes.io/cluster/bsp-eks-cluster11" = "owned"
    Environment                              = "poc"
    Project                                  = "bsp"
    NodeRole                                 = "istio-keycloak"
    Component                                = "infrastructure"
    AZ                                       = "az1"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
  ]
}

# Worker Node 2 - osdu-backend (AZ2)
resource "aws_instance" "eks_node_backend" {
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  subnet_id = data.aws_subnet.private_az2.id

  tags = {
    Name                                     = "osdu-backend"
    "kubernetes.io/cluster/bsp-eks-cluster11" = "owned"
    Environment                              = "poc"
    Project                                  = "bsp"
    NodeRole                                 = "backend"
    Component                                = "application"
    AZ                                       = "az2"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
  ]
}

# Worker Node 3 - osdu-frontend (AZ1)
resource "aws_instance" "eks_node_frontend" {
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  subnet_id = data.aws_subnet.private_az1.id

  tags = {
    Name                                     = "osdu-frontend"
    "kubernetes.io/cluster/bsp-eks-cluster11" = "owned"
    Environment                              = "poc"
    Project                                  = "bsp"
    NodeRole                                 = "frontend"
    Component                                = "presentation"
    AZ                                       = "az1"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
  ]
}

# # Apply labels to nodes after they join the cluster
# resource "null_resource" "label_osdu_istio_keycloak" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       # Wait for node to be ready
#       echo "Waiting for osdu-istio-keycloak node to be ready..."
#       kubectl wait --for=condition=Ready node/osdu-istio-keycloak --timeout=300s
      
#       # Apply labels
#       kubectl label nodes osdu-istio-keycloak node-role=osdu-istio-keycloak --overwrite
#       kubectl label nodes osdu-istio-keycloak component=infrastructure --overwrite
#       kubectl label nodes osdu-istio-keycloak workload=istio --overwrite
#       kubectl label nodes osdu-istio-keycloak workload=keycloak --overwrite
#       kubectl label nodes osdu-istio-keycloak environment=poc --overwrite
      
#       echo "Labels applied to osdu-istio-keycloak node"
#     EOT
#   }

#   depends_on = [aws_instance.eks_node_istio_keycloak]

#   triggers = {
#     node_id = aws_instance.eks_node_istio_keycloak.id
#   }
# }

# resource "null_resource" "label_osdu_backend" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       # Wait for node to be ready
#       echo "Waiting for osdu-backend node to be ready..."
#       kubectl wait --for=condition=Ready node/osdu-backend --timeout=300s
      
#       # Apply labels
#       kubectl label nodes osdu-backend node-role=osdu-backend --overwrite
#       kubectl label nodes osdu-backend component=application --overwrite
#       kubectl label nodes osdu-backend workload=backend --overwrite
#       kubectl label nodes osdu-backend tier=backend --overwrite
#       kubectl label nodes osdu-backend environment=poc --overwrite
      
#       echo "Labels applied to osdu-backend node"
#     EOT
#   }

#   depends_on = [aws_instance.eks_node_backend]

#   triggers = {
#     node_id = aws_instance.eks_node_backend.id
#   }
# }

# resource "null_resource" "label_osdu_frontend" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       # Wait for node to be ready
#       echo "Waiting for osdu-frontend node to be ready..."
#       kubectl wait --for=condition=Ready node/osdu-frontend --timeout=300s
      
#       # Apply labels
#       kubectl label nodes osdu-frontend node-role=osdu-frontend --overwrite
#       kubectl label nodes osdu-frontend component=presentation --overwrite
#       kubectl label nodes osdu-frontend workload=frontend --overwrite
#       kubectl label nodes osdu-frontend tier=frontend --overwrite
#       kubectl label nodes osdu-frontend environment=poc --overwrite
      
#       echo "Labels applied to osdu-frontend node"
#     EOT
#   }

#   depends_on = [aws_instance.eks_node_frontend]

#   triggers = {
#     node_id = aws_instance.eks_node_frontend.id
#   }
# }

# # Output node information
# output "eks_nodes_info" {
#   description = "Information about the EKS nodes and their labels"
#   value = {
#     "osdu-istio-keycloak" = {
#       instance_id = aws_instance.eks_node_istio_keycloak.id
#       private_ip  = aws_instance.eks_node_istio_keycloak.private_ip
#       az          = aws_instance.eks_node_istio_keycloak.availability_zone
#       role        = "Infrastructure (Istio + Keycloak)"
#       labels = [
#         "node-role=osdu-istio-keycloak",
#         "component=infrastructure", 
#         "workload=istio",
#         "workload=keycloak",
#         "environment=poc"
#       ]
#     }
#     "osdu-backend" = {
#       instance_id = aws_instance.eks_node_backend.id
#       private_ip  = aws_instance.eks_node_backend.private_ip
#       az          = aws_instance.eks_node_backend.availability_zone
#       role        = "Application Backend"
#       labels = [
#         "node-role=osdu-backend",
#         "component=application",
#         "workload=backend",
#         "tier=backend", 
#         "environment=poc"
#       ]
#     }
#     "osdu-frontend" = {
#       instance_id = aws_instance.eks_node_frontend.id
#       private_ip  = aws_instance.eks_node_frontend.private_ip
#       az          = aws_instance.eks_node_frontend.availability_zone
#       role        = "Presentation Frontend"
#       labels = [
#         "node-role=osdu-frontend",
#         "component=presentation",
#         "workload=frontend",
#         "tier=frontend",
#         "environment=poc"
#       ]
#     }
#   }
# }

# # Output kubectl commands to verify labels
# output "verify_labels_commands" {
#   description = "Commands to verify node labels"
#   value = {
#     "check_all_nodes" = "kubectl get nodes --show-labels"
#     "check_istio_keycloak" = "kubectl describe node osdu-istio-keycloak"
#     "check_backend" = "kubectl describe node osdu-backend"
#     "check_frontend" = "kubectl describe node osdu-frontend"
#     "get_nodes_by_role" = {
#       "istio_keycloak" = "kubectl get nodes -l node-role=osdu-istio-keycloak"
#       "backend" = "kubectl get nodes -l node-role=osdu-backend"
#       "frontend" = "kubectl get nodes -l node-role=osdu-frontend"
#     }
#   }
# }


# Simple labeling after nodes are created
resource "null_resource" "label_nodes" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for nodes to join cluster..."
      sleep 60
      
      echo "Getting node hostnames from EC2 instances..."
      
      # Get the internal hostnames of our instances
      ISTIO_HOSTNAME=$(aws ec2 describe-instances --instance-ids ${aws_instance.eks_node_istio_keycloak.id} --query 'Reservations[0].Instances[0].PrivateDnsName' --output text)
      BACKEND_HOSTNAME=$(aws ec2 describe-instances --instance-ids ${aws_instance.eks_node_backend.id} --query 'Reservations[0].Instances[0].PrivateDnsName' --output text)
      FRONTEND_HOSTNAME=$(aws ec2 describe-instances --instance-ids ${aws_instance.eks_node_frontend.id} --query 'Reservations[0].Instances[0].PrivateDnsName' --output text)
      
      echo "Hostnames found:"
      echo "Istio/Keycloak: $ISTIO_HOSTNAME"
      echo "Backend: $BACKEND_HOSTNAME"  
      echo "Frontend: $FRONTEND_HOSTNAME"
      
      echo "Waiting for nodes to be ready in Kubernetes..."
      kubectl wait --for=condition=Ready node/$ISTIO_HOSTNAME --timeout=300s
      kubectl wait --for=condition=Ready node/$BACKEND_HOSTNAME --timeout=300s
      kubectl wait --for=condition=Ready node/$FRONTEND_HOSTNAME --timeout=300s
      
      echo "Labeling nodes..."
      
      # Label osdu-istio-keycloak node
      kubectl label node $ISTIO_HOSTNAME node-role=osdu-istio-keycloak --overwrite
      kubectl label node $ISTIO_HOSTNAME component=infrastructure --overwrite
      kubectl label node $ISTIO_HOSTNAME workload=istio --overwrite
      kubectl label node $ISTIO_HOSTNAME workload=keycloak --overwrite
      kubectl label node $ISTIO_HOSTNAME environment=poc --overwrite
      
      # Label osdu-backend node
      kubectl label node $BACKEND_HOSTNAME node-role=osdu-backend --overwrite
      kubectl label node $BACKEND_HOSTNAME component=application --overwrite
      kubectl label node $BACKEND_HOSTNAME workload=backend --overwrite
      kubectl label node $BACKEND_HOSTNAME tier=backend --overwrite
      kubectl label node $BACKEND_HOSTNAME environment=poc --overwrite
      
      # Label osdu-frontend node
      kubectl label node $FRONTEND_HOSTNAME node-role=osdu-frontend --overwrite
      kubectl label node $FRONTEND_HOSTNAME component=presentation --overwrite
      kubectl label node $FRONTEND_HOSTNAME workload=frontend --overwrite
      kubectl label node $FRONTEND_HOSTNAME tier=frontend --overwrite
      kubectl label node $FRONTEND_HOSTNAME environment=poc --overwrite
      
      echo "All nodes labeled successfully!"
      echo "Verifying labels..."
      kubectl get nodes --show-labels | grep -E "(node-role|component)"
    EOT
  }

  depends_on = [
    aws_instance.eks_node_istio_keycloak,
    aws_instance.eks_node_backend,
    aws_instance.eks_node_frontend,
  ]

  triggers = {
    node_ids = "${aws_instance.eks_node_istio_keycloak.id}-${aws_instance.eks_node_backend.id}-${aws_instance.eks_node_frontend.id}"
  }
}