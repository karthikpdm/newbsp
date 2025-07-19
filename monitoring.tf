# monitoring-fixed-vpc-endpoint.tf
# Fixed monitoring configuration with VPC endpoint URL

# 1. Create AWS Managed Prometheus (AMP) Workspace
resource "aws_prometheus_workspace" "bsp_amp" {
  alias = "bsp-prometheus-poc"
  
  tags = {
    Name        = "bsp-prometheus-workspace"
    Environment = "poc"
    Project     = "bsp"
    ManagedBy   = "terraform"
  }
}

# 2. Get AMP VPC Endpoint details
data "aws_vpc_endpoint" "amp" {
  filter {
    name   = "service-name"
    values = ["com.amazonaws.us-east-1.aps-workspaces"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}

# 3. IAM Role for Grafana with custom policy
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
  }
}

# 4. Custom policy for Grafana
resource "aws_iam_policy" "grafana_custom_policy" {
  name        = "bsp-grafana-custom-policy"
  description = "Custom policy for AWS Managed Grafana"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_custom_policy" {
  policy_arn = aws_iam_policy.grafana_custom_policy.arn
  role       = aws_iam_role.grafana_role.name
}

# 5. Policy for Prometheus access
resource "aws_iam_policy" "grafana_prometheus_policy" {
  name        = "bsp-grafana-prometheus-policy"
  description = "Policy for Grafana to access Prometheus workspace"

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
        Resource = aws_prometheus_workspace.bsp_amp.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_prometheus_policy" {
  policy_arn = aws_iam_policy.grafana_prometheus_policy.arn
  role       = aws_iam_role.grafana_role.name
}

# 6. Create AWS Managed Grafana Workspace
resource "aws_grafana_workspace" "bsp_grafana" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana_role.arn
  name                     = "bsp-grafana-poc"
  description              = "BSP Grafana workspace for monitoring EKS cluster"
  
  data_sources = ["PROMETHEUS"]
  
  tags = {
    Name        = "bsp-grafana-workspace"
    Environment = "poc"
    Project     = "bsp"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.grafana_custom_policy,
    aws_iam_role_policy_attachment.grafana_prometheus_policy
  ]
}

# 7. Create monitoring namespace first
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "istio-injection" = "disabled"  # Disable Istio for monitoring
      "environment"     = "poc"
      "component"       = "monitoring"
      "managed-by"      = "terraform"
    }
  }

  depends_on = [
    aws_eks_cluster.main,
    data.aws_eks_cluster_auth.bsp_eks
  ]
}

# 8. IAM Role for Prometheus Service Account (IRSA)
resource "aws_iam_role" "prometheus_role" {
  name = "bsp-prometheus-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_cluster.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:monitoring:prometheus-server"
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 9. Policy for Prometheus to write to AMP
resource "aws_iam_policy" "prometheus_policy" {
  name        = "bsp-prometheus-amp-policy"
  description = "Policy for Prometheus to write metrics to AMP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.bsp_amp.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prometheus_policy" {
  policy_arn = aws_iam_policy.prometheus_policy.arn
  role       = aws_iam_role.prometheus_role.name
}

# 10. Create Kubernetes Service Account for Prometheus
resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus-server"
    namespace = "monitoring"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.prometheus_role.arn
    }
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# 11. Deploy Prometheus with VPC endpoint URL
# Replace the helm_release resource with this corrected version
resource "helm_release" "prometheus_simple" {
  name       = "prometheus-simple"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = "monitoring"
  version    = "25.8.0"

  values = [
    yamlencode({
      # Service account configuration
      serviceAccounts = {
        server = {
          create = false
          name   = kubernetes_service_account.prometheus.metadata[0].name
        }
      }
      
      # Prometheus server configuration
      server = {
        # Use configMapOverrides instead of config (this actually works)
        configMapOverrides = {
          "prometheus.yml" = yamlencode({
            global = {
              scrape_interval = "15s"
              evaluation_interval = "15s"
              external_labels = {
                cluster = aws_eks_cluster.main.name
              }
            }
            
            remote_write = [
              {
                url = "${aws_prometheus_workspace.bsp_amp.prometheus_endpoint}api/v1/remote_write"
                sigv4 = {
                  region = data.aws_region.current.name
                }
                write_relabel_configs = [
                  {
                    source_labels = ["__name__"]
                    regex = "prometheus_.*|up"
                    action = "drop"
                  }
                ]
              }
            ]
            
            scrape_configs = [
              {
                job_name = "prometheus"
                static_configs = [
                  {
                    targets = ["localhost:9090"]
                  }
                ]
              },
              {
                job_name = "kubernetes-nodes"
                kubernetes_sd_configs = [
                  {
                    role = "node"
                  }
                ]
                relabel_configs = [
                  {
                    source_labels = ["__address__"]
                    regex = "(.*):10250"
                    target_label = "__address__"
                    replacement = "$1:9100"
                  },
                  {
                    source_labels = ["__meta_kubernetes_node_name"]
                    target_label = "instance"
                  }
                ]
              },
              {
                job_name = "kubernetes-pods"
                kubernetes_sd_configs = [
                  {
                    role = "pod"
                  }
                ]
                relabel_configs = [
                  {
                    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                    action = "keep"
                    regex = "true"
                  },
                  {
                    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
                    action = "replace"
                    target_label = "__metrics_path__"
                    regex = "(.+)"
                  },
                  {
                    source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
                    action = "replace"
                    regex = "([^:]+)(?::\\d+)?;(\\d+)"
                    replacement = "$1:$2"
                    target_label = "__address__"
                  }
                ]
              }
            ]
          })
        }
        
        # Resource limits
        resources = {
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
        
        # Node selector
        nodeSelector = {
          "node-role" = "osdu-backend"
        }
        
        # Storage
        persistentVolume = {
          enabled = true
          size    = "8Gi"
          storageClass = "gp2"
        }
        
        # Retention
        retention = "7d"
      }
      
      # Disable other components to reduce complexity
      alertmanager = {
        enabled = false
      }
      
      nodeExporter = {
        enabled = true
        resources = {
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
        }
      }
      
      pushgateway = {
        enabled = false
      }
      
      kubeStateMetrics = {
        enabled = true
        resources = {
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
        }
      }
    })
  ]

  wait    = true
  timeout = 300

  depends_on = [
    kubernetes_service_account.prometheus,
    aws_iam_role_policy_attachment.prometheus_policy
  ]
}
# 12. Outputs
output "monitoring_info" {
  description = "Monitoring infrastructure information"
  value = {
    amp_workspace = {
      id                  = aws_prometheus_workspace.bsp_amp.id
      arn                 = aws_prometheus_workspace.bsp_amp.arn
      prometheus_endpoint = aws_prometheus_workspace.bsp_amp.prometheus_endpoint
      vpc_endpoint_url    = "https://${data.aws_vpc_endpoint.amp.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/"
    }
    grafana_workspace = {
      id       = aws_grafana_workspace.bsp_grafana.id
      arn      = aws_grafana_workspace.bsp_grafana.arn
      endpoint = aws_grafana_workspace.bsp_grafana.endpoint
    }
    vpc_endpoint = {
      id       = data.aws_vpc_endpoint.amp.id
      dns_name = data.aws_vpc_endpoint.amp.dns_entry[0].dns_name
    }
  }
}

output "monitoring_verification_commands" {
  description = "Commands to verify monitoring setup"
  value = {
    check_prometheus_pods = "kubectl get pods -n monitoring"
    check_prometheus_service = "kubectl get svc -n monitoring"
    port_forward_prometheus = "kubectl port-forward -n monitoring svc/prometheus-simple-server 9090:80"
    check_helm_releases = "helm list -n monitoring"
    check_namespace_labels = "kubectl get namespace monitoring --show-labels"
    check_prometheus_config = "kubectl get configmap prometheus-simple-server -n monitoring -o yaml | grep -A 10 remote_write"
    test_amp_connectivity = "kubectl exec -n monitoring deployment/prometheus-simple-server -- curl -s -o /dev/null -w '%%{http_code}' https://${data.aws_vpc_endpoint.amp.dns_entry[0].dns_name}/"
  }
}

output "amp_connection_details" {
  description = "AMP connection details for verification"
  value = {
    workspace_id = aws_prometheus_workspace.bsp_amp.id
    vpc_endpoint_dns = data.aws_vpc_endpoint.amp.dns_entry[0].dns_name
    remote_write_url = "https://${data.aws_vpc_endpoint.amp.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/api/v1/remote_write"
    grafana_data_source_url = "https://${data.aws_vpc_endpoint.amp.dns_entry[0].dns_name}/workspaces/${aws_prometheus_workspace.bsp_amp.id}/"
  }
}