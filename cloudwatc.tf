# cloudwatch-logging.tf
# Fixed CloudWatch Container Insights for EKS

# ===================================
# 1. IAM ROLE FOR FLUENT BIT
# ===================================

resource "aws_iam_role" "fluent_bit_role" {
  name = "bsp-fluent-bit-role"

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
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:fluent-bit"
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "bsp-fluent-bit-role"
    Environment = "poc"
  }
}

# ===================================
# 2. IAM POLICY FOR CLOUDWATCH LOGS
# ===================================

resource "aws_iam_policy" "fluent_bit_policy" {
  name = "bsp-fluent-bit-cloudwatch-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fluent_bit_policy_attachment" {
  policy_arn = aws_iam_policy.fluent_bit_policy.arn
  role       = aws_iam_role.fluent_bit_role.name
}

# ===================================
# 3. CLOUDWATCH NAMESPACE
# ===================================

resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
    labels = {
      name = "amazon-cloudwatch"
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# ===================================
# 4. SERVICE ACCOUNT FOR FLUENT BIT
# ===================================

resource "kubernetes_service_account" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = "amazon-cloudwatch"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.fluent_bit_role.arn
    }
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

# ===================================
# 5. FLUENT BIT CONFIGMAP - FIXED VARIABLES
# ===================================

#  Update your FluentBit ConfigMap to use pod names as stream names

resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = "amazon-cloudwatch"
  }

  data = {
    "fluent-bit.conf" = <<-EOF
      [SERVICE]
          Flush                     5
          Grace                     30
          Log_Level                 info
          Daemon                    off
          Parsers_File              parsers.conf
          HTTP_Server               On
          HTTP_Listen               0.0.0.0
          HTTP_Port                 2020
          storage.path              /var/fluent-bit/state/flb-storage/
          storage.sync              normal
          storage.checksum          off
          storage.backlog.mem_limit 5M

      [INPUT]
          Name                tail
          Tag                 application.*
          Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
          Path                /var/log/containers/*.log
          multiline.parser    docker, cri
          DB                  /var/fluent-bit/state/flb_container.db
          Mem_Buf_Limit       50MB
          Skip_Long_Lines     On
          Refresh_Interval    10
          Rotate_Wait         30
          storage.type        filesystem
          Read_from_Head      $${READ_FROM_HEAD}

      [FILTER]
          Name                kubernetes
          Match               application.*
          Kube_URL            https://kubernetes.default.svc:443
          Kube_Tag_Prefix     application.var.log.containers.
          Merge_Log           On
          Merge_Log_Key       log_processed
          K8S-Logging.Parser  On
          K8S-Logging.Exclude Off
          Labels              Off
          Annotations         Off
          Use_Kubelet         On
          Kubelet_Port        10250
          Buffer_Size         0

      # ADD CUSTOM FILTER TO SET STREAM NAME TO POD NAME
      [FILTER]
          Name                modify
          Match               application.*
          Add                 stream_name $${kubernetes_pod_name}

      [OUTPUT]
          Name                cloudwatch_logs
          Match               application.*
          region              $${AWS_REGION}
          log_group_name      /aws/containerinsights/$${CLUSTER_NAME}/application
          log_stream_name     $${stream_name}
          auto_create_group   On
          extra_user_agent    container-insights
    EOF

    "parsers.conf" = <<-EOF
      [PARSER]
          Name                docker
          Format              json
          Time_Key            time
          Time_Format         %Y-%m-%dT%H:%M:%S.%LZ

      [PARSER]
          Name                cri
          Format              regex
          Regex               ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
          Time_Key            time
          Time_Format         %Y-%m-%dT%H:%M:%S.%L%z
    EOF
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}
# ===================================
# 6. FLUENT BIT DAEMONSET
# ===================================

resource "kubernetes_daemonset" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = "amazon-cloudwatch"
    labels = {
      k8s-app                         = "fluent-bit"
      version                         = "v1"
      "kubernetes.io/cluster-service" = "true"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app                         = "fluent-bit"
          version                         = "v1"
          "kubernetes.io/cluster-service" = "true"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.fluent_bit.metadata[0].name

        container {
          name  = "fluent-bit"
          image = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"

          env {
            name  = "AWS_REGION"
            value = data.aws_region.current.name
          }

          env {
            name  = "CLUSTER_NAME"
            value = aws_eks_cluster.main.name
          }

          env {
            name = "HOST_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name  = "READ_FROM_HEAD"
            value = "Off"
          }

          env {
            name  = "READ_FROM_TAIL"
            value = "On"
          }

          resources {
            limits = {
              memory = "200Mi"
            }
            requests = {
              cpu    = "10m"
              memory = "20Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc/"
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlogs"
            mount_path = "/var/logs"
            read_only  = true
          }

          volume_mount {
            name       = "fluent-bit-state"
            mount_path = "/var/fluent-bit/state"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.fluent_bit_config.metadata[0].name
          }
        }

        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlogs"
          host_path {
            path = "/var/logs"
          }
        }

        volume {
          name = "fluent-bit-state"
          host_path {
            path = "/var/fluent-bit/state"
          }
        }

        toleration {
          key      = "node.kubernetes.io/not-ready"
          operator = "Exists"
          effect   = "NoExecute"
          toleration_seconds = 300
        }

        toleration {
          key      = "node.kubernetes.io/unreachable"
          operator = "Exists"
          effect   = "NoExecute"
          toleration_seconds = 300
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.fluent_bit,
    kubernetes_config_map.fluent_bit_config
  ]
}

# ===================================
# 7. OUTPUTS
# ===================================

output "cloudwatch_logging_info" {
  description = "CloudWatch logging configuration information"
  value = {
    log_groups = {
      application_logs = "/aws/containerinsights/${aws_eks_cluster.main.name}/application"
      dataplane_logs   = "/aws/containerinsights/${aws_eks_cluster.main.name}/dataplane"
    }
    fluent_bit_namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
    fluent_bit_role_arn  = aws_iam_role.fluent_bit_role.arn
  }
}