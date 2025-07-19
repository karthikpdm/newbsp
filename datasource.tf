# data-sources.tf
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



# vpc-endpoints.tf
# Essential VPC Endpoints for Private EKS Cluster

# Get current AWS region
# data "aws_region" "current" {}

## vpc-endpoints.tf
# Essential VPC Endpoints for Private EKS Cluster

# Get current AWS region
# data "aws_region" "current" {}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoint" {
  name        = "bsp-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bsp-vpc-endpoint-sg"
    Environment = "poc"
  }
}

# 1. ECR API VPC Endpoint (REQUIRED - for container registry API calls)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "bsp-ecr-api-vpc-endpoint"
    Environment = "poc"
  }
}

# 2. ECR DKR VPC Endpoint (REQUIRED - for pulling container images)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "bsp-ecr-dkr-vpc-endpoint"
    Environment = "poc"
  }
}

# 3. S3 VPC Endpoint (REQUIRED - Gateway endpoint for ECR image layers, FREE)
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
  }
}



# Add these 2 endpoints to your existing data-sources.tf

# 1. AWS Managed Prometheus (AMP) VPC Endpoint - REQUIRED for remote write
resource "aws_vpc_endpoint" "amp" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.aps-workspaces"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "bsp-amp-vpc-endpoint"
    Environment = "poc"
  }
}

# 2. AWS STS VPC Endpoint - REQUIRED for IAM role assumption (IRSA)
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "bsp-sts-vpc-endpoint"
    Environment = "poc"
  }
}


#  1. Grafana Service VPC Endpoint (Primary)
resource "aws_vpc_endpoint" "grafana" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.grafana"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.grafana_vpc_endpoint.id]
  
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

# 2. Grafana Workspace VPC Endpoint (for workspace access)
resource "aws_vpc_endpoint" "grafana_workspace" {
  vpc_id              = data.aws_vpc.existing.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.grafana-workspace"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.grafana_vpc_endpoint.id]
  
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
    Name        = "grafana-workspace-vpc-endpoint"
    Environment = "poc"
    Project     = "bsp"
  }
}

# 3. Security Group for Grafana VPC Endpoints
resource "aws_security_group" "grafana_vpc_endpoint" {
  name_prefix = "grafana-vpc-endpoint-"
  vpc_id      = data.aws_vpc.existing.id
  description = "Security group for Grafana VPC endpoints"

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "grafana-vpc-endpoint-sg"
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
  }
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoint.id
}