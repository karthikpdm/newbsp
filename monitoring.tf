# monitoring-fixed-no-istio.tf
# Fixed monitoring configuration without Istio injection issues

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

# 2. IAM Role for Grafana with custom policy
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

# 3. Custom policy for Grafana
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

# 4. Policy for Prometheus access
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

# 5. Create AWS Managed Grafana Workspace
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

# 6. Update monitoring namespace to DISABLE Istio injection
resource "kubernetes_labels" "monitoring_namespace_labels" {
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "monitoring"
  }
  labels = {
    "istio-injection" = "disabled"  # DISABLE Istio injection for monitoring
    "environment"     = "poc"
    "component"       = "monitoring"
    "managed-by"      = "terraform"
  }

  depends_on = [
    aws_eks_cluster.main,
    data.aws_eks_cluster_auth.bsp_eks
  ]
}

# 7. IAM Role for Prometheus Service Account (IRSA)
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

# 8. Policy for Prometheus to write to AMP
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

# 9. Create Kubernetes Service Account for Prometheus
resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus-server"
    namespace = "monitoring"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.prometheus_role.arn
    }
  }

  depends_on = [kubernetes_labels.monitoring_namespace_labels]
}

# 10. Clean up existing failed releases first
resource "null_resource" "cleanup_failed_releases" {
  provisioner "local-exec" {
    command = <<-EOT
      # Remove failed prometheus releases
      helm uninstall prometheus -n monitoring --ignore-not-found
      helm uninstall prometheus-stack -n monitoring --ignore-not-found
      
      # Wait a bit for cleanup
      sleep 10
      
      # Clean up stuck pods
      kubectl delete pods --all -n monitoring --grace-period=0 --force --ignore-not-found
      
      # Wait for cleanup
      sleep 5
    EOT
  }

  depends_on = [kubernetes_labels.monitoring_namespace_labels]
}

# 11. Deploy Lightweight Prometheus without the problematic kube-prometheus-stack
resource "helm_release" "prometheus_simple" {
  name       = "prometheus-simple"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"  # Simple prometheus chart
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
        # Remote write to AMP
        configMapOverrides = {
          "prometheus.yml" = <<-EOF
            global:
              scrape_interval: 15s
              evaluation_interval: 15s
            
            remote_write:
              - url: ${aws_prometheus_workspace.bsp_amp.prometheus_endpoint}api/v1/remote_write
                sigv4:
                  region: ${data.aws_region.current.name}
            
            scrape_configs:
              - job_name: 'prometheus'
                static_configs:
                  - targets: ['localhost:9090']
              
              - job_name: 'kubernetes-nodes'
                kubernetes_sd_configs:
                  - role: node
                relabel_configs:
                  - source_labels: [__address__]
                    regex: '(.*):10250'
                    target_label: __address__
                    replacement: '$1:9100'
              
              - job_name: 'kubernetes-pods'
                kubernetes_sd_configs:
                  - role: pod
                relabel_configs:
                  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                    action: keep
                    regex: true
          EOF
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
        enabled = false  # Disable for now
      }
    })
  ]

  wait    = true
  timeout = 300

  depends_on = [
    null_resource.cleanup_failed_releases,
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
    }
    grafana_workspace = {
      id       = aws_grafana_workspace.bsp_grafana.id
      arn      = aws_grafana_workspace.bsp_grafana.arn
      endpoint = aws_grafana_workspace.bsp_grafana.endpoint
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
  }
}

output "cleanup_commands" {
  description = "Manual cleanup commands if needed"
  value = {
    remove_failed_releases = "helm uninstall prometheus prometheus-stack -n monitoring --ignore-not-found"
    restart_stuck_pods = "kubectl delete pods --all -n monitoring --grace-period=0 --force"
    check_istio_injection = "kubectl get namespace monitoring --show-labels | grep istio-injection"
  }
}