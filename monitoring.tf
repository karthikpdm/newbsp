# Clean Prometheus setup based on AWS documentation
# Following AWS guide: "Set up ingestion from a new Prometheus server using Helm"
# This configuration avoids dependency cycles and conflicts

# Data sources for existing infrastructure


# Data source for existing EKS cluster
data "aws_eks_cluster" "main" {
  name = "bsp-eks-cluster11"
}

data "aws_eks_cluster_auth" "main" {
  name = "bsp-eks-cluster11"
}

# Data source for existing OIDC provider
data "aws_iam_openid_connect_provider" "eks_cluster" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Data source for existing VPC endpoints security group
data "aws_security_group" "vpc_endpoints" {
  filter {
    name   = "tag:Name" 
    values = ["vpc-endpoints-sg"]
  }
}

# Data source for existing VPC endpoint
data "aws_vpc_endpoint" "aps_workspaces" {
  filter {
    name   = "tag:Name"
    values = ["amp-vpc-endpoint"]
  }
}

# Step 1: Create AWS Managed Prometheus Workspace
resource "aws_prometheus_workspace" "prometheus_workspace" {
  alias = "bsp-prometheus-new"
  
  tags = {
    Name        = "bsp-prometheus-workspace-new"
    Environment = "poc"
    Project     = "bsp"
    ManagedBy   = "terraform"
  }
}

# Step 3: Create IAM role for Prometheus service account (IRSA)
resource "aws_iam_role" "prometheus_ingest_role" {
  name = "prometheus-amp-ingest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks_cluster.arn
        }
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:prometheus:amp-iamproxy-ingest-service-account"
            "${replace(data.aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "prometheus-amp-ingest-role"
    Environment = "poc"
    Project     = "bsp"
  }
}

# IAM policy for AMP ingestion
resource "aws_iam_policy" "prometheus_amp_policy" {
  name        = "PrometheusAMPIngestPolicy"
  description = "Policy for Prometheus to ingest metrics to AMP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata",
          "aps:QueryMetrics"
        ]
        Resource = aws_prometheus_workspace.prometheus_workspace.arn
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "prometheus_policy_attachment" {
  role       = aws_iam_role.prometheus_ingest_role.name
  policy_arn = aws_iam_policy.prometheus_amp_policy.arn
}

# # Configure providers (separate from resource dependencies)
# provider "kubernetes" {
#   host                   = data.aws_eks_cluster.main.endpoint
#   cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
#   token                  = data.aws_eks_cluster_auth.main.token
# }

# provider "helm" {
#   kubernetes {
#     host                   = data.aws_eks_cluster.main.endpoint
#     cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
#     token                  = data.aws_eks_cluster_auth.main.token
#   }
# }

# Step 2: Create Prometheus namespace
resource "kubernetes_namespace" "prometheus_namespace" {
  metadata {
    name = "prometheus"
    labels = {
      "environment" = "poc"
      "component"   = "monitoring"
      "managed-by"  = "terraform"
    }
  }
}

# Prometheus configuration values following AWS documentation
locals {
  prometheus_values = {
    serviceAccounts = {
      server = {
        name = "amp-iamproxy-ingest-service-account"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.prometheus_ingest_role.arn
        }
      }
    }
    
    server = {
      # Remote write configuration as per AWS docs
      remoteWrite = [
        {
          url = "https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.prometheus_workspace.id}/api/v1/remote_write"
          sigv4 = {
            region = data.aws_region.current.name
          }
          queue_config = {
            max_samples_per_send = 1000
            max_shards          = 200
            capacity            = 2500
          }
        }
      ]
      
      # Resource configuration
      resources = {
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
      }
      
      # Storage configuration
      persistentVolume = {
        enabled = true
        size    = "20Gi"
        storageClass = "gp2"
      }
      
      retention = "15d"
    }
    
    # Enable essential components
    nodeExporter = {
      enabled = true
      resources = {
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    }
    
    kubeStateMetrics = {
      enabled = true
      resources = {
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    }
    
    # Disable unnecessary components
    alertmanager = {
      enabled = false
    }
    
    pushgateway = {
      enabled = false
    }
  }
}

# Step 4: Install Prometheus using Helm
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = kubernetes_namespace.prometheus_namespace.metadata[0].name
  version    = "25.8.0"

  values = [yamlencode(local.prometheus_values)]

  wait    = true
  timeout = 600

  depends_on = [
    kubernetes_namespace.prometheus_namespace,
    aws_iam_role_policy_attachment.prometheus_policy_attachment
  ]
}

# Wait for deployment
resource "time_sleep" "wait_for_prometheus" {
  depends_on = [helm_release.prometheus]
  create_duration = "90s"
}

# Optional: Grafana workspace for visualization
resource "aws_iam_role" "grafana_service_role" {
  name = "grafana-amp-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "grafana-amp-service-role"
    Environment = "poc"
    Project     = "bsp"
  }
}

resource "aws_iam_policy" "grafana_amp_policy" {
  name        = "GrafanaAMPPolicy"
  description = "Policy for AWS Managed Grafana to access AMP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace", 
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_policy_attachment" {
  policy_arn = aws_iam_policy.grafana_amp_policy.arn
  role       = aws_iam_role.grafana_service_role.name
}

resource "aws_grafana_workspace" "grafana" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana_service_role.arn
  name                     = "bsp-grafana-new"
  description              = "BSP Grafana workspace for Prometheus monitoring"
  
  data_sources = ["PROMETHEUS", "CLOUDWATCH"]
  
  vpc_configuration {
    security_group_ids = [data.aws_security_group.vpc_endpoints.id]
    subnet_ids         = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  }
  
  tags = {
    Name        = "bsp-grafana-workspace-new"
    Environment = "poc"
    Project     = "bsp"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.grafana_policy_attachment
  ]
}

# Validation
resource "null_resource" "setup_validation" {
  depends_on = [time_sleep.wait_for_prometheus]

  provisioner "local-exec" {
    command = <<-EOT
      echo "🎉 Clean Prometheus setup complete!"
      echo ""
      echo "✅ AWS Documentation Steps Completed:"
      echo "   Step 1: Helm repositories ✓"
      echo "   Step 2: Namespace 'prometheus' created ✓"
      echo "   Step 3: IAM roles configured ✓"
      echo "   Step 4: Prometheus server installed ✓"
      echo ""
      echo "📊 Infrastructure Details:"
      echo "   - EKS Cluster: bsp-eks-cluster11"
      echo "   - AMP Workspace: ${aws_prometheus_workspace.prometheus_workspace.id}"
      echo "   - VPC Endpoint: ${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}"
      echo "   - Grafana: ${aws_grafana_workspace.grafana.endpoint}"
      echo ""
      echo "🔍 Quick Verification:"
      echo "   kubectl get pods -n prometheus"
      echo "   kubectl get svc -n prometheus"
    EOT
  }

  triggers = {
    prometheus_id = helm_release.prometheus.id
    workspace_id = aws_prometheus_workspace.prometheus_workspace.id
  }
}

# Clean outputs without conflicts
output "prometheus_monitoring_setup" {
  description = "Clean Prometheus monitoring setup information"
  value = {
    # AWS Documentation compliance
    aws_guide_steps = {
      step_1_helm_repos = "✅ Referenced prometheus-community charts"
      step_2_namespace = kubernetes_namespace.prometheus_namespace.metadata[0].name
      step_3_iam_roles = aws_iam_role.prometheus_ingest_role.name
      step_4_prometheus = helm_release.prometheus.name
    }
    
    # Infrastructure details
    amp_workspace = {
      id                = aws_prometheus_workspace.prometheus_workspace.id
      arn               = aws_prometheus_workspace.prometheus_workspace.arn
      endpoint          = aws_prometheus_workspace.prometheus_workspace.prometheus_endpoint
      vpc_endpoint_url  = "https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.prometheus_workspace.id}/"
      remote_write_url  = "https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.prometheus_workspace.id}/api/v1/remote_write"
    }
    
    grafana_workspace = {
      id       = aws_grafana_workspace.grafana.id
      endpoint = aws_grafana_workspace.grafana.endpoint
    }
    
    eks_cluster = {
      name     = "bsp-eks-cluster11"
      endpoint = data.aws_eks_cluster.main.endpoint
    }
  }
}

output "verification_commands" {
  description = "Commands to verify the setup"
  value = {
    # Basic verification
    check_namespace = "kubectl get namespace prometheus"
    check_pods = "kubectl get pods -n prometheus"
    check_services = "kubectl get svc -n prometheus"
    
    # Prometheus specific checks
    check_prometheus_config = "kubectl get configmap -n prometheus prometheus-server -o yaml | grep remote_write -A 10"
    check_prometheus_logs = "kubectl logs -n prometheus deployment/prometheus-server -c prometheus-server --tail=50"
    check_service_account = "kubectl get serviceaccount -n prometheus amp-iamproxy-ingest-service-account -o yaml"
    
    # Connectivity tests
    test_vpc_endpoint = "kubectl exec -n prometheus deployment/prometheus-server -c prometheus-server -- nslookup ${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}"
    test_prometheus_health = "kubectl exec -n prometheus deployment/prometheus-server -c prometheus-server -- wget -qO- 'http://localhost:9090/-/healthy'"
    
    # Port forwarding for local access
    port_forward = "kubectl port-forward -n prometheus svc/prometheus-server 9090:80"
    
    # AWS CLI checks
    check_iam_role = "aws iam get-role --role-name prometheus-amp-ingest-role"
    check_amp_workspace = "aws amp describe-workspace --workspace-id ${aws_prometheus_workspace.prometheus_workspace.id}"
  }
}