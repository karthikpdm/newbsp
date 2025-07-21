# # monitoring-fixed.tf
# # Complete fixed monitoring configuration

# # 1. Create AWS Managed Prometheus (AMP) Workspace
# resource "aws_prometheus_workspace" "bsp_amp" {
#   alias = "bsp-prometheus-poc"
  
#   tags = {
#     Name        = "bsp-prometheus-workspace"
#     Environment = "poc"
#     Project     = "bsp"
#     ManagedBy   = "terraform"
#   }
# }

# # 2. FIXED: Enhanced IAM Role for Grafana
# resource "aws_iam_role" "grafana_role" {
#   name = "bsp-grafana-service-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "grafana.amazonaws.com"
#         }
#       }
#     ]
#   })

#   tags = {
#     Name        = "bsp-grafana-service-role"
#     Environment = "poc"
#     Project     = "bsp"
#   }
# }

# # 3. FIXED: Comprehensive policy for Grafana with all required AMP permissions
# resource "aws_iam_policy" "grafana_comprehensive_policy" {
#   name        = "bsp-grafana-comprehensive-policy"
#   description = "Comprehensive policy for AWS Managed Grafana with AMP access"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           # Prometheus permissions - FIXED: Added all required actions
#           "aps:ListWorkspaces",
#           "aps:DescribeWorkspace", 
#           "aps:QueryMetrics",
#           "aps:GetLabels",
#           "aps:GetSeries",
#           "aps:GetMetricMetadata",
#           # CloudWatch permissions
#           "cloudwatch:DescribeAlarmsForMetric",
#           "cloudwatch:DescribeAlarmHistory", 
#           "cloudwatch:DescribeAlarms",
#           "cloudwatch:ListMetrics",
#           "cloudwatch:GetMetricStatistics",
#           "cloudwatch:GetMetricData",
#           # CloudWatch Logs permissions
#           "logs:DescribeLogGroups",
#           "logs:DescribeLogStreams",
#           "logs:GetLogEvents",
#           "logs:StartQuery",
#           "logs:StopQuery", 
#           "logs:GetQueryResults",
#           # EC2 permissions
#           "ec2:DescribeTags",
#           "ec2:DescribeInstances",
#           "ec2:DescribeRegions"
#         ]
#         Resource = "*"
#       },
#       {
#         # FIXED: Specific permission for the AMP workspace
#         Effect = "Allow"
#         Action = [
#           "aps:*"
#         ]
#         Resource = aws_prometheus_workspace.bsp_amp.arn
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "grafana_comprehensive_policy" {
#   policy_arn = aws_iam_policy.grafana_comprehensive_policy.arn
#   role       = aws_iam_role.grafana_role.name
# }

# # 4. FIXED: Create AWS Managed Grafana Workspace with proper configuration
# resource "aws_grafana_workspace" "bsp_grafana" {
#   account_access_type      = "CURRENT_ACCOUNT"
#   authentication_providers = ["AWS_SSO"]
#   permission_type          = "SERVICE_MANAGED"
#   role_arn                 = aws_iam_role.grafana_role.arn
#   name                     = "bsp-grafana-poc"
#   description              = "BSP Grafana workspace for monitoring EKS cluster"
  
#   data_sources = ["PROMETHEUS", "CLOUDWATCH"]
  
#   # VPC Configuration for private access
#   vpc_configuration {
#     security_group_ids = [aws_security_group.vpc_endpoints.id]
#     subnet_ids         = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
#   }
  
#   tags = {
#     Name        = "bsp-grafana-workspace"
#     Environment = "poc"
#     Project     = "bsp"
#     ManagedBy   = "terraform"
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.grafana_comprehensive_policy,
#     aws_vpc_endpoint.aps_workspaces,
#     aws_vpc_endpoint.grafana,
#     aws_vpc_endpoint.grafana_workspace
#   ]
# }

# # 5. Create monitoring namespace
# resource "kubernetes_namespace" "monitoring" {
#   metadata {
#     name = "monitoring"
#     labels = {
#       "istio-injection" = "disabled"
#       "environment"     = "poc"
#       "component"       = "monitoring"
#       "managed-by"      = "terraform"
#     }
#   }

#   depends_on = [
#     aws_eks_cluster.main
#   ]
# }

# # 6. FIXED: IAM Role for Prometheus Service Account (IRSA) with enhanced permissions
# resource "aws_iam_role" "prometheus_role" {
#   name = "bsp-prometheus-service-role"

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
#             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:monitoring:prometheus-server"
#             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })

#   tags = {
#     Name        = "bsp-prometheus-service-role"
#     Environment = "poc"
#     Project     = "bsp"
#   }
# }

# # 7. FIXED: Enhanced policy for Prometheus with all required AMP permissions
# resource "aws_iam_policy" "prometheus_policy" {
#   name        = "bsp-prometheus-amp-policy"
#   description = "Enhanced policy for Prometheus to interact with AMP"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "aps:RemoteWrite",
#           "aps:QueryMetrics",
#           "aps:GetSeries",
#           "aps:GetLabels",
#           "aps:GetMetricMetadata",
#           "aps:ListWorkspaces",
#           "aps:DescribeWorkspace"
#         ]
#         Resource = aws_prometheus_workspace.bsp_amp.arn
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "prometheus_policy" {
#   policy_arn = aws_iam_policy.prometheus_policy.arn
#   role       = aws_iam_role.prometheus_role.name
# }

# # 8. Create Kubernetes Service Account for Prometheus
# resource "kubernetes_service_account" "prometheus" {
#   metadata {
#     name      = "prometheus-server"
#     namespace = "monitoring"
#     annotations = {
#       "eks.amazonaws.com/role-arn" = aws_iam_role.prometheus_role.arn
#     }
#   }

#   depends_on = [kubernetes_namespace.monitoring]
# }

# # 9. Deploy Prometheus using Helm
# resource "helm_release" "prometheus_simple" {
#   name       = "prometheus-simple"
#   repository = "https://prometheus-community.github.io/helm-charts"
#   chart      = "prometheus"
#   namespace  = "monitoring"
#   version    = "25.8.0"

#   values = [
#     yamlencode({
#       serviceAccounts = {
#         server = {
#           create = false
#           name   = kubernetes_service_account.prometheus.metadata[0].name
#         }
#       }
      
#       server = {
#         resources = {
#           limits = {
#             cpu    = "500m"
#             memory = "1Gi"
#           }
#           requests = {
#             cpu    = "250m"
#             memory = "512Mi"
#           }
#         }
        
#         persistentVolume = {
#           enabled = true
#           size    = "8Gi"
#           storageClass = "gp2"
#         }
        
#         retention = "7d"
#       }
      
#       alertmanager = {
#         enabled = false
#       }
      
#       nodeExporter = {
#         enabled = true
#         resources = {
#           limits = {
#             cpu    = "100m"
#             memory = "128Mi"
#           }
#           requests = {
#             cpu    = "50m"
#             memory = "64Mi"
#           }
#         }
#       }
      
#       pushgateway = {
#         enabled = false
#       }
      
#       kubeStateMetrics = {
#         enabled = true
#         resources = {
#           limits = {
#             cpu    = "100m"
#             memory = "128Mi"
#           }
#           requests = {
#             cpu    = "50m"
#             memory = "64Mi"
#           }
#         }
#       }
#     })
#   ]

#   wait    = true
#   timeout = 300

#   depends_on = [
#     kubernetes_service_account.prometheus,
#     aws_iam_role_policy_attachment.prometheus_policy
#   ]
# }

# # 10. Wait for Helm deployment
# resource "time_sleep" "wait_for_helm" {
#   depends_on = [helm_release.prometheus_simple]
#   create_duration = "60s"
# }

# # 11. FIXED: Update Prometheus configuration with correct VPC endpoint URL
# resource "kubernetes_config_map_v1_data" "prometheus_config_patch" {
#   depends_on = [time_sleep.wait_for_helm]

#   metadata {
#     name      = "prometheus-simple-server"
#     namespace = "monitoring"
#   }

#   data = {
#     "prometheus.yml" = yamlencode({
#       global = {
#         scrape_interval = "30s"
#         external_labels = {
#           cluster = aws_eks_cluster.main.name
#         }
#       }
      
#       # FIXED: Use VPC endpoint DNS name instead of public endpoint
#       remote_write = [{
#         url = "https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/remote_write"
#         sigv4 = {
#           region = data.aws_region.current.name
#         }
#       }]
      
#       scrape_configs = [
#         {
#           job_name = "prometheus"
#           static_configs = [{
#             targets = ["localhost:9090"]
#           }]
#         },
#         {
#           job_name = "kubernetes-nodes"
#           kubernetes_sd_configs = [{
#             role = "node"
#           }]
#           relabel_configs = [{
#             source_labels = ["__address__"]
#             regex = "(.+):10250"
#             target_label = "__address__"
#             replacement = "$1:9100"
#           }]
#         },
#         {
#           job_name = "kubernetes-pods" 
#           kubernetes_sd_configs = [{
#             role = "pod"
#           }]
#           relabel_configs = [{
#             source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
#             action = "keep"
#             regex = "true"
#           }]
#         }
#       ]
#     })
#   }

#   force = true
# }

# # 12. Restart Prometheus to apply new configuration
# resource "null_resource" "restart_prometheus" {
#   depends_on = [kubernetes_config_map_v1_data.prometheus_config_patch]

#   provisioner "local-exec" {
#     command = "kubectl rollout restart deployment/prometheus-simple-server -n monitoring"
#   }

#   triggers = {
#     config_content = kubernetes_config_map_v1_data.prometheus_config_patch.data["prometheus.yml"]
#   }
# }

# # 13. Wait for rollout to complete
# resource "null_resource" "wait_for_restart" {
#   depends_on = [null_resource.restart_prometheus]

#   provisioner "local-exec" {
#     command = "kubectl rollout status deployment/prometheus-simple-server -n monitoring --timeout=300s"
#   }

#   triggers = {
#     restart_id = null_resource.restart_prometheus.id
#   }
# }

# # 14. Validation and setup completion
# resource "null_resource" "validate_setup" {
#   depends_on = [null_resource.wait_for_restart]

#   provisioner "local-exec" {
#     command = <<-EOT
#       echo "🎉 Fixed Prometheus setup complete!"
#       echo ""
#       echo "✅ VPC Endpoint DNS: ${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}"
#       echo "✅ AMP Workspace ID: ${aws_prometheus_workspace.bsp_amp.id}"
#       echo "✅ Remote Write URL: https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/remote_write"
#       echo ""
#       echo "🔍 To test DNS resolution:"
#       echo "kubectl exec -n monitoring deployment/prometheus-simple-server -c prometheus-server -- nslookup ${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}"
#       echo ""
#       echo "🔍 To test query access:"
#       echo "kubectl exec -n monitoring deployment/prometheus-simple-server -c prometheus-server -- wget -qO- 'https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/query?query=up'"
#       echo ""
#       echo "📊 Grafana URL: https://${aws_grafana_workspace.bsp_grafana.endpoint}"
#       echo "📈 Grafana Data Source URL: https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/"
#     EOT
#   }

#   triggers = {
#     validation_id = null_resource.wait_for_restart.id
#   }
# }

# # 15. Outputs
# output "monitoring_info_fixed" {
#   description = "Fixed monitoring infrastructure information"
#   value = {
#     amp_workspace = {
#       id                  = aws_prometheus_workspace.bsp_amp.id
#       arn                 = aws_prometheus_workspace.bsp_amp.arn
#       prometheus_endpoint = aws_prometheus_workspace.bsp_amp.prometheus_endpoint
#       vpc_endpoint_url    = "https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/"
#       remote_write_url    = "https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/remote_write"
#     }
#     grafana_workspace = {
#       id       = aws_grafana_workspace.bsp_grafana.id
#       arn      = aws_grafana_workspace.bsp_grafana.arn
#       endpoint = aws_grafana_workspace.bsp_grafana.endpoint
#     }
#     vpc_endpoint = {
#       id       = aws_vpc_endpoint.aps_workspaces.id
#       dns_name = aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name
#     }
#   }
# }

# output "troubleshooting_commands" {
#   description = "Commands to verify the fixed setup"
#   value = {
#     test_dns_resolution = "kubectl exec -n monitoring deployment/prometheus-simple-server -c prometheus-server -- nslookup ${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}"
#     test_vpc_endpoint_connectivity = "kubectl exec -n monitoring deployment/prometheus-simple-server -c prometheus-server -- wget -qO- 'https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/'"
#     test_amp_query = "kubectl exec -n monitoring deployment/prometheus-simple-server -c prometheus-server -- wget -qO- 'https://${aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/query?query=up'"
#     check_prometheus_remote_write = "kubectl exec -n monitoring deployment/prometheus-simple-server -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_total'"
#     restart_prometheus = "kubectl rollout restart deployment/prometheus-simple-server -n monitoring"
#     check_grafana_workspace = "aws grafana describe-workspace --workspace-id ${aws_grafana_workspace.bsp_grafana.id}"
#     port_forward_prometheus = "kubectl port-forward -n monitoring svc/prometheus-simple-server 9090:80"
#   }
# }




















# Prometheus setup based on AWS documentation with existing VPC endpoints
# Following AWS guide: "Set up ingestion from a new Prometheus server using Helm"

# Data sources for existing infrastructure
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

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

# Data source for existing EKS cluster
data "aws_eks_cluster" "main" {
  name = "bsp-eks-cluster"
}

data "aws_eks_cluster_auth" "main" {
  name = "bsp-eks-cluster"
}

# Data source for existing OIDC provider
data "aws_iam_openid_connect_provider" "eks_cluster" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Data source for existing VPC endpoints
data "aws_vpc_endpoint" "aps_workspaces" {
  filter {
    name   = "tag:Name"
    values = ["amp-vpc-endpoint"]
  }
}

data "aws_security_group" "vpc_endpoints" {
  filter {
    name   = "tag:Name"
    values = ["bsp-vpc-endpoints-sg"]
  }
}

# Step 1: Create AWS Managed Prometheus Workspace
resource "aws_prometheus_workspace" "bsp_amp" {
  alias = "bsp-prometheus-poc"
  
  tags = {
    Name        = "bsp-prometheus-workspace"
    Environment = "poc"
    Project     = "bsp"
    ManagedBy   = "terraform"
  }
}

# Step 2: Create Prometheus namespace (as per AWS docs Step 2)
resource "kubernetes_namespace" "prometheus_namespace" {
  metadata {
    name = "prometheus"
    labels = {
      "istio-injection" = "disabled"
      "environment"     = "poc"
      "component"       = "monitoring"
      "managed-by"      = "terraform"
    }
  }
}

# Step 3: Set up IAM roles for service accounts (as per AWS docs Step 3)
# Create the amp-iamproxy-ingest-role as specified in AWS documentation
resource "aws_iam_role" "amp_iamproxy_ingest_role" {
  name = "amp-iamproxy-ingest-role"

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
    Name        = "amp-iamproxy-ingest-role"
    Environment = "poc"
    Project     = "bsp"
  }
}

# IAM policy for Amazon Managed Service for Prometheus ingestion
resource "aws_iam_policy" "amp_ingest_policy" {
  name        = "AMPIngestPolicy"
  description = "Policy for ingesting metrics to Amazon Managed Service for Prometheus"

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
        Resource = aws_prometheus_workspace.bsp_amp.arn
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "amp_ingest_policy_attachment" {
  role       = aws_iam_role.amp_iamproxy_ingest_role.name
  policy_arn = aws_iam_policy.amp_ingest_policy.arn
}

# Configure Kubernetes and Helm providers
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# Step 1 from AWS docs: Add Helm repositories (done via Terraform)
resource "helm_repository" "prometheus_community" {
  name = "prometheus-community"
  url  = "https://prometheus-community.github.io/helm-charts"
}

resource "helm_repository" "kube_state_metrics" {
  name = "kube-state-metrics"
  url  = "https://kubernetes.github.io/kube-state-metrics"
}

# Step 4: Set up the new server and start ingesting metrics
# Create Prometheus values file as specified in AWS documentation
locals {
  # Using VPC endpoint DNS name instead of public endpoint for private cluster
  prometheus_values = {
    serviceAccounts = {
      server = {
        name = "amp-iamproxy-ingest-service-account"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.amp_iamproxy_ingest_role.arn
        }
      }
    }
    server = {
      remoteWrite = [
        {
          # Use VPC endpoint DNS name for private cluster connectivity
          url = "https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/remote_write"
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
      
      # Additional configurations for better performance in private cluster
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
      
      persistentVolume = {
        enabled = true
        size    = "20Gi"
        storageClass = "gp2"
      }
      
      retention = "15d"
    }
    
    # Enable node exporter for comprehensive metrics
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
    
    # Enable kube-state-metrics
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
    
    # Disable alertmanager and pushgateway as per basic setup
    alertmanager = {
      enabled = false
    }
    
    pushgateway = {
      enabled = false
    }
  }
}

# Install Prometheus using Helm as specified in AWS documentation
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = helm_repository.prometheus_community.name
  chart      = "prometheus"
  namespace  = kubernetes_namespace.prometheus_namespace.metadata[0].name
  version    = "25.8.0"

  values = [yamlencode(local.prometheus_values)]

  wait    = true
  timeout = 600

  depends_on = [
    kubernetes_namespace.prometheus_namespace,
    aws_iam_role_policy_attachment.amp_ingest_policy_attachment,
    helm_repository.prometheus_community,
    helm_repository.kube_state_metrics
  ]
}

# Wait for deployment to stabilize
resource "time_sleep" "wait_for_prometheus" {
  depends_on = [helm_release.prometheus]
  create_duration = "60s"
}

# Validation resource to check setup
resource "null_resource" "validate_prometheus_setup" {
  depends_on = [time_sleep.wait_for_prometheus]

  provisioner "local-exec" {
    command = <<-EOT
      echo "🎉 Prometheus setup complete as per AWS documentation!"
      echo ""
      echo "✅ Following AWS guide: 'Set up ingestion from a new Prometheus server using Helm'"
      echo "✅ Namespace: prometheus (Step 2 ✓)"
      echo "✅ IAM Role: amp-iamproxy-ingest-role (Step 3 ✓)"
      echo "✅ Service Account: amp-iamproxy-ingest-service-account (Step 3 ✓)"
      echo "✅ Helm Chart: prometheus-community/prometheus (Step 4 ✓)"
      echo ""
      echo "📋 Setup Details:"
      echo "   - AMP Workspace ID: ${aws_prometheus_workspace.bsp_amp.id}"
      echo "   - VPC Endpoint URL: https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}"
      echo "   - Remote Write URL: https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/remote_write"
      echo "   - EKS Cluster: bsp-eks-cluster"
      echo "   - Region: ${data.aws_region.current.name}"
      echo ""
      echo "🔍 Verification Commands:"
      echo "   kubectl get pods -n prometheus"
      echo "   kubectl get svc -n prometheus"
      echo "   kubectl logs -n prometheus deployment/prometheus-server -c prometheus-server"
    EOT
  }

  triggers = {
    prometheus_release = helm_release.prometheus.version
    workspace_id = aws_prometheus_workspace.bsp_amp.id
  }
}

# Optional: Create Grafana workspace for visualization
resource "aws_iam_role" "grafana_role" {
  name = "bsp-grafana-service-role"

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
    Name        = "bsp-grafana-service-role"
    Environment = "poc"
    Project     = "bsp"
  }
}

resource "aws_iam_policy" "grafana_policy" {
  name        = "bsp-grafana-amp-policy"
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
      },
      {
        Effect = "Allow"
        Action = [
          "aps:*"
        ]
        Resource = aws_prometheus_workspace.bsp_amp.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_policy" {
  policy_arn = aws_iam_policy.grafana_policy.arn
  role       = aws_iam_role.grafana_role.name
}

resource "aws_grafana_workspace" "bsp_grafana" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana_role.arn
  name                     = "bsp-grafana-poc"
  description              = "BSP Grafana workspace for monitoring EKS cluster"
  
  data_sources = ["PROMETHEUS", "CLOUDWATCH"]
  
  vpc_configuration {
    security_group_ids = [data.aws_security_group.vpc_endpoints.id]
    subnet_ids         = [data.aws_subnet.private_az1.id, data.aws_subnet.private_az2.id]
  }
  
  tags = {
    Name        = "bsp-grafana-workspace"
    Environment = "poc"
    Project     = "bsp"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.grafana_policy
  ]
}

# Outputs following AWS documentation structure
output "prometheus_setup_info" {
  description = "Prometheus setup information following AWS documentation"
  value = {
    # Step 1: Helm repositories added ✓
    helm_repositories = {
      prometheus_community = helm_repository.prometheus_community.name
      kube_state_metrics   = helm_repository.kube_state_metrics.name
    }
    
    # Step 2: Namespace created ✓
    namespace = kubernetes_namespace.prometheus_namespace.metadata[0].name
    
    # Step 3: IAM roles configured ✓
    iam_role = {
      name = aws_iam_role.amp_iamproxy_ingest_role.name
      arn  = aws_iam_role.amp_iamproxy_ingest_role.arn
    }
    
    # Step 4: Prometheus server installed ✓
    prometheus_release = {
      name      = helm_release.prometheus.name
      namespace = helm_release.prometheus.namespace
      version   = helm_release.prometheus.version
    }
    
    # AMP workspace details
    amp_workspace = {
      id                  = aws_prometheus_workspace.bsp_amp.id
      arn                 = aws_prometheus_workspace.bsp_amp.arn
      prometheus_endpoint = aws_prometheus_workspace.bsp_amp.prometheus_endpoint
      vpc_endpoint_url    = "https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/"
      remote_write_url    = "https://${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/remote_write"
    }
    
    # Grafana workspace
    grafana_workspace = {
      id       = aws_grafana_workspace.bsp_grafana.id
      endpoint = aws_grafana_workspace.bsp_grafana.endpoint
    }
  }
}

output "aws_documentation_verification" {
  description = "Commands to verify setup as per AWS documentation"
  value = {
    # Verify Step 1: Check Helm repositories
    check_helm_repos = "helm repo list"
    
    # Verify Step 2: Check namespace
    check_namespace = "kubectl get namespace prometheus"
    
    # Verify Step 3: Check service account and IAM role
    check_service_account = "kubectl get serviceaccount -n MONITORING amp-iamproxy-ingest-service-account -o yaml"
    check_iam_role = "aws iam get-role --role-name amp-iamproxy-ingest-role"
    
    # Verify Step 4: Check Prometheus installation
    check_prometheus_pods = "kubectl get pods -n prometheus"
    check_prometheus_config = "kubectl get configmap -n prometheus prometheus-server -o yaml"
    check_prometheus_logs = "kubectl logs -n prometheus deployment/prometheus-server -c prometheus-server --tail=50"
    
    # Test remote write functionality
    test_remote_write = "kubectl exec -n prometheus deployment/prometheus-server -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_total'"
    
    # Port forward for local access
    port_forward_prometheus = "kubectl port-forward -n prometheus svc/prometheus-server 9090:80"
    
    # Test VPC endpoint connectivity
    test_vpc_endpoint = "kubectl exec -n prometheus deployment/prometheus-server -c prometheus-server -- nslookup ${data.aws_vpc_endpoint.aps_workspaces.dns_entry[0].dns_name}"
  }
}