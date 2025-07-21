# # # cloudwatch-logging.tf
# # # Fixed CloudWatch Container Insights for EKS

# # # ===================================
# # # 1. IAM ROLE FOR FLUENT BIT
# # # ===================================

# # resource "aws_iam_role" "fluent_bit_role" {
# #   name = "bsp-fluent-bit-role"

# #   assume_role_policy = jsonencode({
# #     Version = "2012-10-17"
# #     Statement = [
# #       {
# #         Action = "sts:AssumeRoleWithWebIdentity"
# #         Effect = "Allow"
# #         Principal = {
# #           Federated = aws_iam_openid_connect_provider.eks_cluster.arn
# #         }
# #         Condition = {
# #           StringEquals = {
# #             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:fluent-bit"
# #             "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
# #           }
# #         }
# #       }
# #     ]
# #   })

# #   tags = {
# #     Name = "bsp-fluent-bit-role"
# #     Environment = "poc"
# #   }
# # }

# # # ===================================
# # # 2. IAM POLICY FOR CLOUDWATCH LOGS
# # # ===================================

# # resource "aws_iam_policy" "fluent_bit_policy" {
# #   name = "bsp-fluent-bit-cloudwatch-policy1"

# #   policy = jsonencode({
# #     Version = "2012-10-17"
# #     Statement = [
# #       {
# #         Effect = "Allow"
# #         Action = [
# #           "logs:CreateLogGroup",
# #           "logs:CreateLogStream",
# #           "logs:PutLogEvents",
# #           "logs:DescribeLogStreams",
# #           "logs:DescribeLogGroups"
# #         ]
# #         Resource = "*"
# #       }
# #     ]
# #   })
# # }

# # resource "aws_iam_role_policy_attachment" "fluent_bit_policy_attachment" {
# #   policy_arn = aws_iam_policy.fluent_bit_policy.arn
# #   role       = aws_iam_role.fluent_bit_role.name
# # }

# # # ===================================
# # # 3. CLOUDWATCH NAMESPACE
# # # ===================================

# # resource "kubernetes_namespace" "amazon_cloudwatch" {
# #   metadata {
# #     name = "amazon-cloudwatch"
# #     labels = {
# #       name = "amazon-cloudwatch"
# #     }
# #   }

# #   depends_on = [aws_eks_cluster.main]
# # }

# # # ===================================
# # # 4. SERVICE ACCOUNT FOR FLUENT BIT
# # # ===================================

# # resource "kubernetes_service_account" "fluent_bit" {
# #   metadata {
# #     name      = "fluent-bit"
# #     namespace = "amazon-cloudwatch"
# #     annotations = {
# #       "eks.amazonaws.com/role-arn" = aws_iam_role.fluent_bit_role.arn
# #     }
# #   }

# #   depends_on = [kubernetes_namespace.amazon_cloudwatch]
# # }

# # # ===================================
# # # 5. FLUENT BIT CONFIGMAP - FIXED VARIABLES
# # # ===================================

# # #  Update your FluentBit ConfigMap to use pod names as stream names

# # resource "kubernetes_config_map" "fluent_bit_config" {
# #   metadata {
# #     name      = "fluent-bit-config"
# #     namespace = "amazon-cloudwatch"
# #   }

# #   data = {
# #     "fluent-bit.conf" = <<-EOF
# #       [SERVICE]
# #           Flush                     5
# #           Grace                     30
# #           Log_Level                 info
# #           Daemon                    off
# #           Parsers_File              parsers.conf
# #           HTTP_Server               On
# #           HTTP_Listen               0.0.0.0
# #           HTTP_Port                 2020
# #           storage.path              /var/fluent-bit/state/flb-storage/
# #           storage.sync              normal
# #           storage.checksum          off
# #           storage.backlog.mem_limit 5M

# #       [INPUT]
# #           Name                tail
# #           Tag                 application.*
# #           Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
# #           Path                /var/log/containers/*.log
# #           multiline.parser    docker, cri
# #           DB                  /var/fluent-bit/state/flb_container.db
# #           Mem_Buf_Limit       50MB
# #           Skip_Long_Lines     On
# #           Refresh_Interval    10
# #           Rotate_Wait         30
# #           storage.type        filesystem
# #           Read_from_Head      $${READ_FROM_HEAD}

# #       [FILTER]
# #           Name                kubernetes
# #           Match               application.*
# #           Kube_URL            https://kubernetes.default.svc:443
# #           Kube_Tag_Prefix     application.var.log.containers.
# #           Merge_Log           On
# #           Merge_Log_Key       log_processed
# #           K8S-Logging.Parser  On
# #           K8S-Logging.Exclude Off
# #           Labels              Off
# #           Annotations         Off
# #           Use_Kubelet         On
# #           Kubelet_Port        10250
# #           Buffer_Size         0

# #       # ADD CUSTOM FILTER TO SET STREAM NAME TO POD NAME
# #       [FILTER]
# #           Name                modify
# #           Match               application.*
# #           Add                 stream_name $${kubernetes_pod_name}

# #       [OUTPUT]
# #           Name                cloudwatch_logs
# #           Match               application.*
# #           region              $${AWS_REGION}
# #           log_group_name      /aws/containerinsights/$${CLUSTER_NAME}/application
# #           log_stream_name     $${stream_name}
# #           auto_create_group   On
# #           extra_user_agent    container-insights
# #     EOF

# #     "parsers.conf" = <<-EOF
# #       [PARSER]
# #           Name                docker
# #           Format              json
# #           Time_Key            time
# #           Time_Format         %Y-%m-%dT%H:%M:%S.%LZ

# #       [PARSER]
# #           Name                cri
# #           Format              regex
# #           Regex               ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
# #           Time_Key            time
# #           Time_Format         %Y-%m-%dT%H:%M:%S.%L%z
# #     EOF
# #   }

# #   depends_on = [kubernetes_namespace.amazon_cloudwatch]
# # }
# # # ===================================
# # # 6. FLUENT BIT DAEMONSET
# # # ===================================

# # resource "kubernetes_daemonset" "fluent_bit" {
# #   metadata {
# #     name      = "fluent-bit"
# #     namespace = "amazon-cloudwatch"
# #     labels = {
# #       k8s-app                         = "fluent-bit"
# #       version                         = "v1"
# #       "kubernetes.io/cluster-service" = "true"
# #     }
# #   }

# #   spec {
# #     selector {
# #       match_labels = {
# #         k8s-app = "fluent-bit"
# #       }
# #     }

# #     template {
# #       metadata {
# #         labels = {
# #           k8s-app                         = "fluent-bit"
# #           version                         = "v1"
# #           "kubernetes.io/cluster-service" = "true"
# #         }
# #       }

# #       spec {
# #         service_account_name = kubernetes_service_account.fluent_bit.metadata[0].name

# #         container {
# #           name  = "fluent-bit"
# #           image = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"

# #           env {
# #             name  = "AWS_REGION"
# #             value = data.aws_region.current.name
# #           }

# #           env {
# #             name  = "CLUSTER_NAME"
# #             value = aws_eks_cluster.main.name
# #           }

# #           env {
# #             name = "HOST_NAME"
# #             value_from {
# #               field_ref {
# #                 field_path = "spec.nodeName"
# #               }
# #             }
# #           }

# #           env {
# #             name  = "READ_FROM_HEAD"
# #             value = "Off"
# #           }

# #           env {
# #             name  = "READ_FROM_TAIL"
# #             value = "On"
# #           }

# #           resources {
# #             limits = {
# #               memory = "200Mi"
# #             }
# #             requests = {
# #               cpu    = "10m"
# #               memory = "20Mi"
# #             }
# #           }

# #           volume_mount {
# #             name       = "config"
# #             mount_path = "/fluent-bit/etc/"
# #           }

# #           volume_mount {
# #             name       = "varlibdockercontainers"
# #             mount_path = "/var/lib/docker/containers"
# #             read_only  = true
# #           }

# #           volume_mount {
# #             name       = "varlog"
# #             mount_path = "/var/log"
# #             read_only  = true
# #           }

# #           volume_mount {
# #             name       = "varlogs"
# #             mount_path = "/var/logs"
# #             read_only  = true
# #           }

# #           volume_mount {
# #             name       = "fluent-bit-state"
# #             mount_path = "/var/fluent-bit/state"
# #           }
# #         }

# #         volume {
# #           name = "config"
# #           config_map {
# #             name = kubernetes_config_map.fluent_bit_config.metadata[0].name
# #           }
# #         }

# #         volume {
# #           name = "varlibdockercontainers"
# #           host_path {
# #             path = "/var/lib/docker/containers"
# #           }
# #         }

# #         volume {
# #           name = "varlog"
# #           host_path {
# #             path = "/var/log"
# #           }
# #         }

# #         volume {
# #           name = "varlogs"
# #           host_path {
# #             path = "/var/logs"
# #           }
# #         }

# #         volume {
# #           name = "fluent-bit-state"
# #           host_path {
# #             path = "/var/fluent-bit/state"
# #           }
# #         }

# #         toleration {
# #           key      = "node.kubernetes.io/not-ready"
# #           operator = "Exists"
# #           effect   = "NoExecute"
# #           toleration_seconds = 300
# #         }

# #         toleration {
# #           key      = "node.kubernetes.io/unreachable"
# #           operator = "Exists"
# #           effect   = "NoExecute"
# #           toleration_seconds = 300
# #         }
# #       }
# #     }
# #   }

# #   depends_on = [
# #     kubernetes_service_account.fluent_bit,
# #     kubernetes_config_map.fluent_bit_config
# #   ]
# # }

# # # ===================================
# # # 7. OUTPUTS
# # # ===================================

# # output "cloudwatch_logging_info" {
# #   description = "CloudWatch logging configuration information"
# #   value = {
# #     log_groups = {
# #       application_logs = "/aws/containerinsights/${aws_eks_cluster.main.name}/application"
# #       dataplane_logs   = "/aws/containerinsights/${aws_eks_cluster.main.name}/dataplane"
# #     }
# #     fluent_bit_namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
# #     fluent_bit_role_arn  = aws_iam_role.fluent_bit_role.arn
# #   }
# # }



























# fluent-bit-logging.tf

# # Get current AWS account ID and region
# data "aws_caller_identity" "current" {}
# data "aws_region" "current" {}

# fluent-bit-logging.tf

# Note: data sources for account ID and region are already in main.tf

# IAM Policy for Fluent Bit CloudWatch Logs
resource "aws_iam_policy" "fluent_bit_cloudwatch_policy" {
  name        = "FluentBitCloudWatchLogsPolicy"
  description = "Policy for Fluent Bit to write logs to CloudWatch"

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
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "FluentBitCloudWatchLogsPolicy"
    Environment = "poc"
  }
}

# IAM Role for Fluent Bit Service Account (IRSA)
resource "aws_iam_role" "fluent_bit_role" {
  name = "fluent-bit-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_cluster.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:fluent-bit"
            "${replace(aws_iam_openid_connect_provider.eks_cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "fluent-bit-role"
    Environment = "poc"
  }

  depends_on = [aws_iam_openid_connect_provider.eks_cluster]
}

# Attach CloudWatch policy to Fluent Bit role
resource "aws_iam_role_policy_attachment" "fluent_bit_cloudwatch_attachment" {
  policy_arn = aws_iam_policy.fluent_bit_cloudwatch_policy.arn
  role       = aws_iam_role.fluent_bit_role.name
}

# Use kubectl provider to deploy Kubernetes resources
resource "kubectl_manifest" "fluent_bit_service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "fluent-bit"
      namespace = "kube-system"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.fluent_bit_role.arn
      }
    }
  })

  depends_on = [aws_iam_role.fluent_bit_role]
}

resource "kubectl_manifest" "fluent_bit_cluster_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name = "fluent-bit-read"
    }
    rules = [
      {
        apiGroups = [""]
        resources = ["namespaces", "pods", "pods/logs", "nodes", "nodes/proxy"]
        verbs     = ["get", "list", "watch"]
      }
    ]
  })
}

resource "kubectl_manifest" "fluent_bit_cluster_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = "fluent-bit-read"
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = "fluent-bit-read"
    }
    subjects = [
      {
        kind      = "ServiceAccount"
        name      = "fluent-bit"
        namespace = "kube-system"
      }
    ]
  })

  depends_on = [
    kubectl_manifest.fluent_bit_service_account,
    kubectl_manifest.fluent_bit_cluster_role
  ]
}

resource "kubectl_manifest" "fluent_bit_config" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "fluent-bit-config"
      namespace = "kube-system"
    }
    data = {
      "fluent-bit.conf" = <<-EOT
        [SERVICE]
            Flush         5
            Log_Level     info
            Daemon        off
            Parsers_File  parsers.conf
            HTTP_Server   On
            HTTP_Listen   0.0.0.0
            HTTP_Port     2020
            storage.path  /var/fluent-bit/state/flb-storage/
            storage.sync  normal
            storage.checksum off
            storage.backlog.mem_limit 5M

        [INPUT]
            Name              tail
            Tag               kube.*
            Path              /var/log/containers/*.log
            multiline.parser  docker, cri
            DB                /var/fluent-bit/state/flb_kube.db
            Mem_Buf_Limit     50MB
            Skip_Long_Lines   On
            Refresh_Interval  10
            Rotate_Wait       30
            storage.type      filesystem
            Read_from_Head    false

        [FILTER]
            Name                kubernetes
            Match               kube.*
            Kube_URL            https://kubernetes.default.svc:443
            Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
            Kube_Tag_Prefix     kube.var.log.containers.
            Merge_Log           On
            Merge_Log_Key       log_processed
            K8S-Logging.Parser  On
            K8S-Logging.Exclude Off
            Labels              Off
            Annotations         Off
            Use_Kubelet         On
            Kubelet_Port        10250
            Buffer_Size         0

        # Single dynamic output for ALL namespaces
        [OUTPUT]
            Name                cloudwatch_logs
            Match               kube.*
            region              ${data.aws_region.current.name}
            log_group_name      /aws/eks/${aws_eks_cluster.main.name}/${kubernetes["namespace_name"]}
            log_stream_name     ${kubernetes["pod_name"]}
            auto_create_group   true
            log_retention_days  7
            log_key             log
            extra_user_agent    container-insights
      EOT

      "parsers.conf" = <<-EOT
        [PARSER]
            Name        docker
            Format      json
            Time_Key    time
            Time_Format %Y-%m-%dT%H:%M:%S.%LZ

        [PARSER]
            Name        cri
            Format      regex
            Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
            Time_Key    time
            Time_Format %Y-%m-%dT%H:%M:%S.%L%z

        [PARSER]
            Name    syslog
            Format  regex
            Regex   ^\<(?<pri>[0-9]+)\>(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$
            Time_Key time
            Time_Format %b %d %H:%M:%S
      EOT
    }
  })
}

resource "kubectl_manifest" "fluent_bit_cluster_info" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "fluent-bit-cluster-info"
      namespace = "kube-system"
    }
    data = {
      "cluster.name" = aws_eks_cluster.main.name
      "logs.region"  = data.aws_region.current.name
      "http.server"  = "On"
      "http.port"    = "2020"
      "read.head"    = "Off"
      "read.tail"    = "On"
    }
  })
}

resource "kubectl_manifest" "fluent_bit_daemonset" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata = {
      name      = "fluent-bit"
      namespace = "kube-system"
      labels = {
        "k8s-app"                       = "fluent-bit-logging"
        "version"                       = "v1"
        "kubernetes.io/cluster-service" = "true"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "k8s-app" = "fluent-bit-logging"
        }
      }
      template = {
        metadata = {
          labels = {
            "k8s-app"                       = "fluent-bit-logging"
            "version"                       = "v1"
            "kubernetes.io/cluster-service" = "true"
          }
        }
        spec = {
          serviceAccount                   = "fluent-bit"
          serviceAccountName               = "fluent-bit"
          hostNetwork                      = true
          dnsPolicy                        = "ClusterFirstWithHostNet"
          terminationGracePeriodSeconds    = 10
          tolerations = [
            {
              key      = "node-role.kubernetes.io/master"
              operator = "Exists"
              effect   = "NoSchedule"
            },
            {
              operator = "Exists"
              effect   = "NoExecute"
            },
            {
              operator = "Exists"
              effect   = "NoSchedule"
            }
          ]
          containers = [
            {
              name            = "fluent-bit"
              image           = "amazon/aws-for-fluent-bit:2.32.0"
              imagePullPolicy = "Always"
              env = [
                {
                  name = "AWS_REGION"
                  valueFrom = {
                    configMapKeyRef = {
                      name = "fluent-bit-cluster-info"
                      key  = "logs.region"
                    }
                  }
                },
                {
                  name = "CLUSTER_NAME"
                  valueFrom = {
                    configMapKeyRef = {
                      name = "fluent-bit-cluster-info"
                      key  = "cluster.name"
                    }
                  }
                },
                {
                  name = "HTTP_SERVER"
                  valueFrom = {
                    configMapKeyRef = {
                      name = "fluent-bit-cluster-info"
                      key  = "http.server"
                    }
                  }
                },
                {
                  name = "HTTP_PORT"
                  valueFrom = {
                    configMapKeyRef = {
                      name = "fluent-bit-cluster-info"
                      key  = "http.port"
                    }
                  }
                },
                {
                  name = "READ_FROM_HEAD"
                  valueFrom = {
                    configMapKeyRef = {
                      name = "fluent-bit-cluster-info"
                      key  = "read.head"
                    }
                  }
                },
                {
                  name = "READ_FROM_TAIL"
                  valueFrom = {
                    configMapKeyRef = {
                      name = "fluent-bit-cluster-info"
                      key  = "read.tail"
                    }
                  }
                },
                {
                  name = "HOST_NAME"
                  valueFrom = {
                    fieldRef = {
                      fieldPath = "spec.nodeName"
                    }
                  }
                },
                {
                  name = "HOSTNAME"
                  valueFrom = {
                    fieldRef = {
                      apiVersion = "v1"
                      fieldPath  = "metadata.name"
                    }
                  }
                },
                {
                  name  = "CI_VERSION"
                  value = "k8s/1.3.26"
                }
              ]
              resources = {
                limits = {
                  memory = "200Mi"
                }
                requests = {
                  cpu    = "100m"
                  memory = "100Mi"
                }
              }
              volumeMounts = [
                {
                  name      = "fluentbitstate"
                  mountPath = "/var/fluent-bit/state"
                },
                {
                  name      = "varlog"
                  mountPath = "/var/log"
                  readOnly  = true
                },
                {
                  name      = "varlibdockercontainers"
                  mountPath = "/var/lib/docker/containers"
                  readOnly  = true
                },
                {
                  name      = "fluent-bit-config"
                  mountPath = "/fluent-bit/etc/"
                },
                {
                  name      = "runlogjournal"
                  mountPath = "/run/log/journal"
                  readOnly  = true
                },
                {
                  name      = "dmesg"
                  mountPath = "/var/log/dmesg"
                  readOnly  = true
                }
              ]
            }
          ]
          volumes = [
            {
              name = "fluentbitstate"
              hostPath = {
                path = "/var/fluent-bit/state"
              }
            },
            {
              name = "varlog"
              hostPath = {
                path = "/var/log"
              }
            },
            {
              name = "varlibdockercontainers"
              hostPath = {
                path = "/var/lib/docker/containers"
              }
            },
            {
              name = "fluent-bit-config"
              configMap = {
                name = "fluent-bit-config"
              }
            },
            {
              name = "runlogjournal"
              hostPath = {
                path = "/run/log/journal"
              }
            },
            {
              name = "dmesg"
              hostPath = {
                path = "/var/log/dmesg"
              }
            }
          ]
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.fluent_bit_service_account,
    kubectl_manifest.fluent_bit_cluster_role_binding,
    kubectl_manifest.fluent_bit_config,
    kubectl_manifest.fluent_bit_cluster_info,
    aws_iam_role_policy_attachment.fluent_bit_cloudwatch_attachment
  ]
}

# Output the IAM role ARN for reference
output "fluent_bit_role_arn" {
  description = "ARN of the Fluent Bit IAM role"
  value       = aws_iam_role.fluent_bit_role.arn
}

output "fluent_bit_verification_commands" {
  description = "Commands to verify Fluent Bit deployment"
  value = {
    check_pods         = "kubectl get pods -n kube-system -l k8s-app=fluent-bit-logging"
    check_logs         = "kubectl logs -n kube-system -l k8s-app=fluent-bit-logging"
    check_config       = "kubectl get configmap fluent-bit-config -n kube-system -o yaml"
    list_log_groups    = "aws logs describe-log-groups --log-group-name-prefix '/aws/eks/${aws_eks_cluster.main.name}/'"
    test_log_creation  = "kubectl run test-nginx --image=nginx --restart=Never && sleep 30 && kubectl logs test-nginx && kubectl delete pod test-nginx"
  }
}

output "expected_log_groups" {
  description = "Expected CloudWatch log groups to be created"
  value = [
    "/aws/eks/${aws_eks_cluster.main.name}/default",
    "/aws/eks/${aws_eks_cluster.main.name}/kube-system", 
    "/aws/eks/${aws_eks_cluster.main.name}/istio-system",
    "/aws/eks/${aws_eks_cluster.main.name}/istio-gateway",
    "/aws/eks/${aws_eks_cluster.main.name}/prometheus",
    "/aws/eks/${aws_eks_cluster.main.name}/kube-public",
    "/aws/eks/${aws_eks_cluster.main.name}/kube-node-lease"
  ]
}