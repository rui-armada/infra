terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"
}

provider "kind" {}

locals {
  config = yamldecode(file("${path.module}/clusters.yaml"))

  # Flatten teams × environments into a map of clusters
  # Key format: "<team>-<env>" (e.g. "bestversion-dev")
  clusters = { for entry in flatten([
    for team in local.config.teams : [
      for env in team.environments : {
        key  = "${team.name}-${env.name}"
        team = team.name
        env  = env.name
      }
    ]
  ]) : entry.key => entry }

  # Auto-assign ports starting from a base (avoids conflicts)
  base_http_port   = 3000
  base_argocd_port = 8080
  cluster_keys     = sort(keys(local.clusters))
  cluster_ports = { for idx, key in local.cluster_keys : key => {
    host_port_http   = local.base_http_port + idx
    host_port_argocd = local.base_argocd_port + idx
  }}
}

module "cluster" {
  source   = "../modules/cluster"
  for_each = local.clusters

  cluster_name     = each.key
  host_port_http   = local.cluster_ports[each.key].host_port_http
  host_port_argocd = local.cluster_ports[each.key].host_port_argocd
  repo_url         = local.config.repo_url
  repo_path        = "platform/apps"
  target_revision  = "main"
}

output "clusters" {
  value = { for name, cluster in module.cluster : name => {
    endpoint   = cluster.cluster_endpoint
    argocd_url = cluster.argocd_url
    app_url    = cluster.app_url
  }}
}
