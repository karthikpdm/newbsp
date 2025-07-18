# monitoring.tf
# AWS Managed Prometheus (AMP) and Managed Grafana with Helm Prometheus


# 2. Create AWS Managed Grafana Workspace
resource "aws_grafana_workspace" "bsp_grafana" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana_role.arn
  name                     = "bsp-grafana-poc"
  description              = "BSP Grafana workspace for monitoring EKS cluster"
  
  data_sources = ["PROMETHEUS"]
  
  # Optional: Enable additional data sources
  # data_sources = ["PROMETHEUS", "CLOUDWATCH"]
  
  notification_destinations = ["SNS"]  # Optional
  
  tags = {
    Name        = "bsp-grafana-workspace"
    Environment = "poc"
    Project     = "bsp"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_iam_role_policy_attachment.grafana_policy]
}

# 3. IAM Role for Grafana
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

# 4. Attach AWS managed policy for Grafana
resource "aws_iam_role_policy_attachment" "grafana_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonGrafanaServiceRole"
  role       = aws_iam_role.grafana_role.name
}

# 5. Custom policy for Prometheus access
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

  tags = {
    Name        = "bsp-grafana-prometheus-policy"
    Environment = "poc"
  }
}

resource "aws_iam_role_policy_attachment" "grafana_prometheus_policy" {
  policy_arn = aws_iam_policy.grafana_prometheus_policy.arn
  role       = aws_iam_role.grafana_role.name
}




# 6. Create namespace for monitoring
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "istio-injection" = "enabled"
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




##########################################################################################################


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

  tags = {
    Name        = "bsp-prometheus-service-role"
    Environment = "poc"
  }
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

  tags = {
    Name        = "bsp-prometheus-amp-policy"
    Environment = "poc"
  }
}

resource "aws_iam_role_policy_attachment" "prometheus_policy" {
  policy_arn = aws_iam_policy.prometheus_policy.arn
  role       = aws_iam_role.prometheus_role.name
}

# 9. Create Kubernetes Service Account for Prometheus
resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus-server"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.prometheus_role.arn
    }
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# 10. Deploy Prometheus using Helm
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "56.6.2"  # Use latest stable version

  # Custom values for AMP integration
  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          serviceAccount = {
            create = false
            name   = kubernetes_service_account.prometheus.metadata[0].name
          }
          
          # Remote write to AWS Managed Prometheus
          remoteWrite = [
            {
              url = "${aws_prometheus_workspace.bsp_amp.prometheus_endpoint}api/v1/remote_write"
              sigv4 = {
                region = data.aws_region.current.name
              }
              writeRelabelConfigs = [
                {
                  sourceLabels = ["__name__"]
                  regex        = "up|prometheus_.*"
                  action       = "drop"
                }
              ]
            }
          ]
          
          # Storage configuration - reduced for cost optimization
          retention = "7d"
          
          # Resource limits
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
          
          # Node selector for monitoring node
          nodeSelector = {
            "node-role" = "osdu-backend"  # Deploy on backend node
          }
        }
      }
      
      # Grafana configuration (optional - can be disabled since using managed Grafana)
      grafana = {
        enabled = false  # Disable since using AWS Managed Grafana
      }
      
      # AlertManager configuration
      alertmanager = {
        alertmanagerSpec = {
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
          nodeSelector = {
            "node-role" = "osdu-backend"
          }
        }
      }
      
      # Node Exporter configuration
      nodeExporter = {
        enabled = true
      }
      
      # Kube State Metrics configuration
      kubeStateMetrics = {
        enabled = true
      }
      
      # Prometheus Operator configuration
      prometheusOperator = {
        resources = {
          limits = {
            cpu    = "200m"
            memory = "200Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "100Mi"
          }
        }
        nodeSelector = {
          "node-role" = "osdu-istio-keycloak"  # Deploy on infrastructure node
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_service_account.prometheus,
    aws_iam_role_policy_attachment.prometheus_policy
  ]
}

# 11. Deploy additional monitoring components
resource "helm_release" "prometheus_adapter" {
  name       = "prometheus-adapter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-adapter"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "4.9.0"

  values = [
    yamlencode({
      prometheus = {
        url = "http://prometheus-kube-prometheus-prometheus.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local"
        port = 9090
      }
      nodeSelector = {
        "node-role" = "osdu-istio-keycloak"
      }
    })
  ]

  depends_on = [helm_release.prometheus]
}

# 12. Create ServiceMonitor for EKS nodes
resource "kubernetes_manifest" "eks_node_servicemonitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "eks-nodes"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
      labels = {
        app = "node-exporter"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "node-exporter"
        }
      }
      endpoints = [
        {
          port = "http-metrics"
          path = "/metrics"
        }
      ]
    }
  }

  depends_on = [helm_release.prometheus]
}

# 13. Outputs
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
    prometheus_namespace = kubernetes_namespace.monitoring.metadata[0].name
    prometheus_service_account = "${kubernetes_namespace.monitoring.metadata[0].name}/${kubernetes_service_account.prometheus.metadata[0].name}"
  }
}

output "grafana_access_instructions" {
  description = "Instructions to access Grafana"
  value = {
    grafana_url = aws_grafana_workspace.bsp_grafana.endpoint
    data_source_url = aws_prometheus_workspace.bsp_amp.prometheus_endpoint
    authentication = "Use AWS SSO to log in to Grafana"
    prometheus_data_source_config = "Add Prometheus data source with URL: ${aws_prometheus_workspace.bsp_amp.prometheus_endpoint}"
  }
}

output "monitoring_verification_commands" {
  description = "Commands to verify monitoring setup"
  value = {
    check_prometheus_pods = "kubectl get pods -n ${kubernetes_namespace.monitoring.metadata[0].name}"
    check_prometheus_service = "kubectl get svc -n ${kubernetes_namespace.monitoring.metadata[0].name}"
    port_forward_prometheus = "kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/prometheus-kube-prometheus-prometheus 9090:9090"
    check_servicemonitors = "kubectl get servicemonitors -n ${kubernetes_namespace.monitoring.metadata[0].name}"
  }
}