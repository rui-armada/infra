terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }
  }
  required_version = ">= 1.0"
}

variable "cluster_name" {
  description = "Name of the Kind cluster"
  type        = string
}

variable "host_port_http" {
  description = "Host port for app traffic (maps to NodePort 30000)"
  type        = number
  default     = 3000
}

variable "host_port_argocd" {
  description = "Host port for Argo CD UI (maps to NodePort 30080)"
  type        = number
  default     = 8080
}

variable "platform_repo" {
  description = "Git repository URL for the platform App of Apps (infra tools)"
  type        = string
}

variable "platform_path" {
  description = "Path in the platform repo containing ArgoCD Application manifests"
  type        = string
  default     = "platform/apps"
}

variable "app_name" {
  description = "Name of the team application"
  type        = string
}

variable "app_repo" {
  description = "Git repository URL for the team's application"
  type        = string
}

variable "app_chart_path" {
  description = "Path to the Helm chart in the team's repo"
  type        = string
}

variable "app_branch" {
  description = "Git branch to track for the team's app"
  type        = string
  default     = "main"
}

# --- Kind Cluster ---

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      extra_port_mappings {
        container_port = 30000
        host_port      = var.host_port_http
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30080
        host_port      = var.host_port_argocd
        protocol       = "TCP"
      }
    }
  }
}

# --- Argo CD (bootstrap via Helm CLI) ---

resource "null_resource" "argocd" {
  provisioner "local-exec" {
    command = <<-EOT
      helm repo add argo https://argoproj.github.io/argo-helm --force-update && \
      helm upgrade --install argocd argo/argo-cd \
        --version 7.7.15 \
        --namespace argocd --create-namespace \
        --kube-context kind-${var.cluster_name} \
        --set server.service.type=NodePort \
        --set server.service.nodePortHttp=30080 \
        --set 'configs.params.server\.insecure=true' \
        --wait --timeout 10m
    EOT
  }

  depends_on = [kind_cluster.this]
}

# --- App of Apps (bootstraps platform infra: istio, prometheus, cert-manager) ---

resource "null_resource" "app_of_apps" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply --context kind-${var.cluster_name} -f - <<EOF
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: platform
        namespace: argocd
      spec:
        project: default
        source:
          repoURL: ${var.platform_repo}
          targetRevision: main
          path: ${var.platform_path}
        destination:
          server: https://kubernetes.default.svc
          namespace: argocd
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
            - CreateNamespace=true
      EOF
    EOT
  }

  depends_on = [null_resource.argocd]
}

# --- Team Application (deploys from team's repo Helm chart) ---

resource "null_resource" "team_app" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply --context kind-${var.cluster_name} -f - <<EOF
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: ${var.app_name}
        namespace: argocd
      spec:
        project: default
        source:
          repoURL: ${var.app_repo}
          targetRevision: ${var.app_branch}
          path: ${var.app_chart_path}
        destination:
          server: https://kubernetes.default.svc
          namespace: ${var.app_name}
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
            - CreateNamespace=true
      EOF
    EOT
  }

  depends_on = [null_resource.argocd]
}

# --- Outputs ---

output "cluster_name" {
  value = kind_cluster.this.name
}

output "cluster_endpoint" {
  value = kind_cluster.this.endpoint
}

output "argocd_url" {
  value = "http://localhost:${var.host_port_argocd}"
}

output "app_url" {
  value = "http://localhost:${var.host_port_http}"
}
