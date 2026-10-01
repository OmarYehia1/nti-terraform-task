# 1. Traefik Ingress Controller via Helm
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  namespace        = "kube-system"
  create_namespace = true
  wait             = false

  set {
    name  = "api.dashboard"
    value = "true"
  }

  set {
    name  = "api.insecure"
    value = "true"
  }

  set {
    name  = "ingressRoute.dashboard.enabled"
    value = "true"
  }

  set {
    name  = "ingressRoute.dashboard.matchRule"
    value = "PathPrefix(`/dashboard`) || PathPrefix(`/api`)"
  }

  set {
    name  = "ingressRoute.dashboard.entryPoints"
    value = "{web}"
  }
}
resource "kubernetes_config_map" "bastion_info" {
  metadata {
    name      = "bastion-info"
    namespace = "default"
  }

  data = {
    "index.html" = "<h1>AWS Bastion Host IP: ${aws_instance.bastion.public_ip}</h1>"
  }
}

# 2. NGINX Deployment (the actual app)
resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx-deployment"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          image = "nginx:latest"
          name  = "nginx"

          port {
            container_port = 80
          }

          volume_mount {
            name       = "bastion-info"
            mount_path = "/usr/share/nginx/html"
          }
        }

        volume {
          name = "bastion-info"
          config_map {
            name = kubernetes_config_map.bastion_info.metadata[0].name
          }
        }
      }
    }
  }
}

# 3. NGINX Internal Service
resource "kubernetes_service" "nginx_service" {
  metadata {
    name      = "nginx-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# 4. Traefik Ingress (Routes traffic from Traefik to the NGINX Service)
resource "kubernetes_ingress_v1" "app_ingress" {
  metadata {
    name      = "app-ingress"
    namespace = "default"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.nginx_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}