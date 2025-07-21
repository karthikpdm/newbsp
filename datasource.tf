# vpc-endpoints-consolidated.tf
# Complete VPC Endpoints and Security Groups for Private EKS → AMP → Grafana

# ===================================
# DATA SOURCES
# ===================================

# Data source for existing VPC
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["pw-vpc-poc"]
  }
}

# Data source for private subnet AZ1
data "aws_subnet" "private_az1" {
  filter {
    name   = "tag:Name"
    values = ["pw-private-subnet-az1-poc"]
  }
}

# Data source for private subnet AZ2
data "aws_subnet" "private_az2" {
  filter {
    name   = "tag:Name"
    values = ["pw-private-subnet-az2-poc"]
  }
}

# Get both private route tables
data "aws_route_table" "private_az1" {
  filter {
    name   = "tag:Name"
    values = ["pw-private-route-table-az1-poc"]
  }
}

data "aws_route_table" "private_az2" {
  filter {
    name   = "tag:Name"
    values = ["pw-private-route-table-az2-poc"]
  }
}

# # Get current AWS region
# data "aws_region" "current" {}

# # Get current AWS caller identity
# data "aws_caller_identity" "current" {}

# ===================================
# SECURITY GROUPS
# ===================================

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  name        = "bsp-eks-clusters1-sg1"
  description = "Security group for EKS cluster control plane"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "bsp-eks-cluster-sg"
    Environment = "poc"
    Project     = "bsp"
  }
}

# EKS Worker Nodes Security Group
resource "aws_security_group" "eks_nodes" {
  name        = "bsp-eks-node-sg1"
  description = "Security group for EKS worker nodes"
  vpc_id      = data.aws_vpc.main.id

  # Allow all traffic between nodes
  ingress {
    description = "All traffic from nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow traffic from cluster security group
  ingress {
    description     = "All traffic from cluster"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # SSH access from VPC
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "bsp-eks-nodes-sg"
    Environment = "poc"
    Project     = "bsp"
  }
}

# Enhanced Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "vpc-endpoints-"
  vpc_id      = data.aws_vpc.main.id
  description = "Security group for VPC endpoints"

  # HTTPS from VPC CIDR
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  # HTTPS from EKS cluster security group
  ingress {
    description     = "HTTPS from EKS cluster"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # HTTPS from EKS nodes security group
  ingress {
    description     = "HTTPS from EKS nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  # HTTP from VPC (some services might need this)
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "vpc-endpoints-sg"
    Environment = "poc"
    Project     = "bsp"
  }
}

# Additional security group rules (separate resources to avoid conflicts)
resource "aws_security_group_rule" "cluster_to_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "Allow all traffic from nodes to cluster"
}

# ===================================
# VPC ENDPOINTS - CRITICAL FOR PRIVATE EKS
# ===================================

# 1. ECR API VPC Endpoint (REQUIRED - for container registry API calls)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  
  tags = {
    Name        = "bsp-ecr-api-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "ECR-API-Access"
  }
}

# 2. ECR DKR VPC Endpoint (REQUIRED - for pulling container images)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  
  tags = {
    Name        = "bsp-ecr-dkr-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "ECR-Image-Pull"
  }
}

# 3. S3 VPC Endpoint (REQUIRED - Gateway endpoint for ECR image layers, FREE)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [
    data.aws_route_table.private_az1.id,
    data.aws_route_table.private_az2.id
  ]
  
  tags = {
    Name        = "bsp-s3-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "ECR-Layers"
  }
}

# 4. STS VPC Endpoint (REQUIRED - for IAM role authentication with AMP)
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "bsp-sts-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "IAM-Authentication"
  }
}

# 5. Amazon Managed Prometheus (APS) VPC Endpoint (CRITICAL - for Prometheus metrics)
resource "aws_vpc_endpoint" "aps_workspaces" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.aps-workspaces"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  # Enhanced policy with all required AMP permissions
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries", 
          "aps:GetLabels",
          "aps:GetMetricMetadata",
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:RemoteWrite"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "bsp-amp-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "Prometheus-to-AMP"
  }
}

# 6. Grafana Service VPC Endpoint (CRITICAL - for Grafana dashboard access)
resource "aws_vpc_endpoint" "grafana" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.grafana"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "grafana:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "bsp-grafana-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "Grafana-Service"
  }
}

# 7. Grafana Workspace VPC Endpoint (CRITICAL - for workspace access)
resource "aws_vpc_endpoint" "grafana_workspace" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.grafana-workspace"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "bsp-grafana-workspace-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "Grafana-Workspace"
  }
}

# 8. CloudWatch Logs VPC Endpoint (RECOMMENDED - for application logs)
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "bsp-logs-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
    Purpose     = "CloudWatch-Logs"
  }
}

# ===================================
# OUTPUTS
# ===================================

output "essential_vpc_endpoints" {
  description = "Essential VPC endpoints for private EKS → AMP → Grafana"
  value = {
    # ECR endpoints for container operations
    ecr_api_endpoint_id = aws_vpc_endpoint.ecr_api.id
    ecr_dkr_endpoint_id = aws_vpc_endpoint.ecr_dkr.id
    s3_endpoint_id      = aws_vpc_endpoint.s3.id
    
    # Critical for Prometheus → AMP flow
    sts_endpoint_id       = aws_vpc_endpoint.sts.id
    aps_endpoint_id       = aws_vpc_endpoint.aps_workspaces.id
    aps_endpoint_dns      = aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name
    
    # Critical for Grafana access
    grafana_endpoint_id         = aws_vpc_endpoint.grafana.id
    grafana_workspace_endpoint_id = aws_vpc_endpoint.grafana_workspace.id
    
    # Optional but recommended
    logs_endpoint_id = aws_vpc_endpoint.logs.id
  }
}

output "security_groups" {
  description = "Security group IDs for EKS and VPC endpoints"
  value = {
    eks_cluster_sg_id   = aws_security_group.eks_cluster.id
    eks_nodes_sg_id     = aws_security_group.eks_nodes.id
    vpc_endpoints_sg_id = aws_security_group.vpc_endpoints.id
  }
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}