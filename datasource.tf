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