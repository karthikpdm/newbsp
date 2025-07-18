resource "null_resource" "wait_for_ingressgateway" {
  depends_on = [helm_release.istio_ingressgateway]
  provisioner "local-exec" {
    command = "echo 'Waiting for istio-ingressgateway to become available...'"
  }
}

data "kubernetes_service" "istio_gateway" {
  metadata {
    name      = "istio-ingressgateway"
    namespace = "istio-gateway"
  }
  depends_on = [
    null_resource.wait_for_ingressgateway,
    helm_release.istio_ingressgateway
  ]
}

locals {
  istio_gateway_domain = try(
    data.kubernetes_service.istio_gateway.status[0].load_balancer[0].ingress[0].hostname,
    null
  )
}



output "domain-name" {
  value      = local.istio_gateway_domain
  depends_on = [helm_release.istio_ingressgateway]
}

output "istio_gateway_dns" {
  value      = data.kubernetes_service.istio_gateway.status[0].load_balancer[0].ingress[0].hostname
  depends_on = [helm_release.istio_ingressgateway]
}




# Creating for minio
resource "kubernetes_manifest" "minio-virtual-service" {
  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "osdu-ir-install-minio"
      namespace = "default"
    }
    spec = {
      hosts    = ["minio.${local.istio_gateway_domain}"]
      gateways = ["minio-gateway"]
      http = [
        {
          match = [{ uri = { prefix = "/" } }]
          route = [
            {
              destination = {
                host = "minio.default.svc.cluster.local"
                port = { number = 9000 }
              }
            }
          ]
        }
      ]
    }
  }
  depends_on = [helm_release.istio_ingressgateway]
}

# Creating for Apache Airflow
resource "kubernetes_manifest" "airflow_virtual_service" {
  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "airflow"
      namespace = "default"
    }
    spec = {
      hosts    = ["airflow.${local.istio_gateway_domain}"]
      gateways = ["airflow-gateway"]
      http = [
        {
          match = [{ uri = { prefix = "/" } }]
          route = [
            {
              destination = {
                host = "airflow.default.svc.cluster.local"
                port = { number = 8080 }
              }
            }
          ]
        }
      ]
    }
  }
  depends_on = [helm_release.istio_ingressgateway]
}

# Creating for Keycloak
resource "kubernetes_manifest" "keycloak_virtual_service" {
  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "osdu-ir-install-keycloak"
      namespace = "default"
    }
    spec = {
      hosts    = ["keycloak.${local.istio_gateway_domain}"]
      gateways = ["keycloak-gateway"]
      http = [
        {
          match = [{ uri = { prefix = "/" } }]
          route = [
            {
              destination = {
                host = "keycloak.default.svc.cluster.local"
                port = { number = 80 }
              }
            }
          ]
        }
      ]
    }
  }
  depends_on = [helm_release.istio_ingressgateway]
}

# Creating for s3
resource "kubernetes_manifest" "s3_virtual_service" {
  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "osdu-ir-install-s3"
      namespace = "default"
    }
    spec = {
      hosts    = ["s3.${local.istio_gateway_domain}"]
      gateways = ["s3-gateway"]
      http = [
        {
          match = [{ uri = { prefix = "/" } }]
          route = [
            {
              destination = {
                host = "s3.default.svc.cluster.local"
                port = { number = 9000 }
              }
            }
          ]
        }
      ]
    }
  }
  depends_on = [helm_release.istio_ingressgateway]
}

# Creating for all OSDU microservices

# Grouping all services in a list
locals {
  osdu_services = [
    "config", "crs-catalog", "crs-conversion", "dataset", "eds-dms", "entitlements",
    "file", "indexer", "legal", "notification", "partition", "policy", "register",
    "schema", "search", "secret", "seismic-store", "storage", "unit",
    "well-delivery", "wellbore", "wellbore-worker", "workflow"
  ]
}

#Creating for each service in the osdu_services
resource "kubernetes_manifest" "osdu_virtual_services" {
  for_each = toset(local.osdu_services)

  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = each.key
      namespace = "default"
    }
    spec = {
      hosts    = ["osdu.${local.istio_gateway_domain}"]
      gateways = ["service-gateway"]
      http = [
        {
          match = [{ uri = { prefix = "/${each.key}" } }]
          route = [
            {
              destination = {
                host = "osdu.default.svc.cluster.local" # shared service
                port = { number = 80 }
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.istio_ingressgateway]
}

