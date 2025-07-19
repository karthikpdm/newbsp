# data-sources.tf - Fixed version

# Data source for existing VPC
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["bsp-vpc-poc"]
  }
}

# Data source for private subnet AZ1
data "aws_subnet" "private_az1" {
  filter {
    name   = "tag:Name"
    values = ["bsp-private-subnet-az1-poc"]
  }
}

# Data source for private subnet AZ2
data "aws_subnet" "private_az2" {
  filter {
    name   = "tag:Name"
    values = ["bsp-private-subnet-az2-poc"]
  }
}

# Get current AWS region
# data "aws_region" "current" {}

# # Get current AWS caller identity
# data "aws_caller_identity" "current" {}

# FIXED: Security Group for VPC Endpoints (moved here for proper dependency)
# This was originally in your vpc-endpoints file but had issues

# Get both private route tables
data "aws_route_table" "private_az1" {
  filter {
    name   = "tag:Name"
    values = ["bsp-private-route-table-az1-poc"]
  }
}

data "aws_route_table" "private_az2" {
  filter {
    name   = "tag:Name"
    values = ["bsp-private-route-table-az2-poc"]
  }
}

# VPC Endpoints Configuration

# 1. ECR API VPC Endpoint (REQUIRED - for container registry API calls)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "bsp-ecr-api-vpc-endpoint"
    Environment = "poc"
    Project = "bsp"
  }
}

# 2. ECR DKR VPC Endpoint (REQUIRED - for pulling container images)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "bsp-ecr-dkr-vpc-endpoint"
    Environment = "poc"
    Project = "bsp"
  }
}

# 3. S3 VPC Endpoint (REQUIRED - Gateway endpoint for ECR image layers, FREE)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.existing.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [
    data.aws_route_table.private_az1.id,
    data.aws_route_table.private_az2.id
  ]
  
  tags = {
    Name = "bsp-s3-vpc-endpoint"
    Environment = "poc"
    Project = "bsp"
  }
}

# FIXED: 4. Amazon Managed Prometheus (APS) VPC Endpoint
resource "aws_vpc_endpoint" "aps_workspaces" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.aps-workspaces"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  # FIXED: Enhanced policy with all required permissions
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
    Name        = "amp-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
  }
}

# 5. Grafana Service VPC Endpoint
resource "aws_vpc_endpoint" "grafana" {
  vpc_id              = data.aws_vpc.existing.id
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
    Name        = "grafana-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
  }
}

# 6. Grafana Workspace VPC Endpoint
resource "aws_vpc_endpoint" "grafana_workspace" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.grafana-workspace"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "grafana-workspace-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
  }
}

# Outputs
output "essential_vpc_endpoints" {
  description = "Essential VPC Endpoints for private EKS cluster"
  value = {
    ecr_api_endpoint_id = aws_vpc_endpoint.ecr_api.id
    ecr_dkr_endpoint_id = aws_vpc_endpoint.ecr_dkr.id
    s3_endpoint_id      = aws_vpc_endpoint.s3.id
    aps_endpoint_id     = aws_vpc_endpoint.aps_workspaces.id
    aps_endpoint_dns    = aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name
  }
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}