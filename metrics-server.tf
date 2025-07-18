# resource "helm_release" "metrics_server" {
#   name       = "metrics-server"
#   namespace  = "monitoring"
#   repository = "https://kubernetes-sigs.github.io/metrics-server/"
#   chart      = "metrics-server"
#   version    = var.metrics_server_version # You can update this as needed

#   values = [
#     yamlencode({
#       args = [
#         "--kubelet-insecure-tls",  # required for some EKS setups
#         "--kubelet-preferred-address-types=InternalIP"
#       ]
#     })
#   ]

#   set {
#     name  = "metrics.enabled"
#     value = "true"
#   }
# }

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}


resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "monitoring"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"

  values = [
    yamlencode({
      args = [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP"
      ]
      
      # Schedule on Istio node group
      nodeSelector = {
        "node-role" = "osdu-istio-keycloak"
      }
      
      # Tolerate Istio node taints
      # tolerations = [
      #   {
      #     key      = "node-role"
      #     operator = "Equal"
      #     value    = "osdu-istio-keycloak"
      #     effect   = "NoSchedule"
      #   }
      # ]
    })
  ]

  set {
    name  = "metrics.enabled"
    value = "true"
  }
}