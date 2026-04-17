# Remote state for App cluster
data "terraform_remote_state" "app" {
  backend = "s3"
  config = {
    bucket = "shopflow-terraform-state-122610497964"
    key    = "app/terraform.tfstate"
    region = "eu-west-1"
  }
}

# Remote state for Observability cluster
data "terraform_remote_state" "observability" {
  backend = "s3"
  config = {
    bucket = "shopflow-terraform-state-122610497964"
    key    = "observability/terraform.tfstate"
    region = "eu-west-1"
  }
}

locals {
  gitops_repo_path = "../../../shopflow-gitops"
  ecr_registry_url = split("/", data.terraform_remote_state.shared.outputs.ecr_repository_urls["frontend"])[0]
  services         = ["frontend", "cart-service", "order-service", "payment-service", "product-service", "user-service"]
}

# Render app-cluster.yaml
resource "local_file" "app_cluster_manifest" {
  content = templatefile("${local.gitops_repo_path}/templates/app-cluster.yaml.tpl", {
    repo_url             = "https://github.com/saranca14/shopflow-gitops.git"
    app_cluster_endpoint = data.terraform_remote_state.app.outputs.cluster_endpoint
  })
  filename = "${local.gitops_repo_path}/clusters/platform/argocd/apps/app-cluster.yaml"
}

# Render observability-app.yaml
resource "local_file" "observability_app_manifest" {
  content = templatefile("${local.gitops_repo_path}/templates/observability-app.yaml.tpl", {
    repo_url             = "https://github.com/saranca14/shopflow-gitops.git"
    obs_cluster_endpoint = data.terraform_remote_state.observability.outputs.cluster_endpoint
  })
  filename = "${local.gitops_repo_path}/clusters/platform/argocd/apps/observability-app.yaml"
}

# Render clusters/app/kustomization.yaml
resource "local_file" "app_kustomization" {
  content = templatefile("${local.gitops_repo_path}/templates/kustomization.app.yaml.tpl", {
    ecr_registry_url = local.ecr_registry_url
    services         = local.services
  })
  filename = "${local.gitops_repo_path}/clusters/app/kustomization.yaml"
}

# Automated Git Push
resource "null_resource" "git_sync" {
  depends_on = [
    local_file.app_cluster_manifest,
    local_file.observability_app_manifest,
    local_file.app_kustomization
  ]

  triggers = {
    app_cluster      = local_file.app_cluster_manifest.content_sha1
    obs_app          = local_file.observability_app_manifest.content_sha1
    app_kustomize    = local_file.app_kustomization.content_sha1
  }

  provisioner "local-exec" {
    command = <<EOT
      cd ${local.gitops_repo_path} && \
      git add . && \
      if [ -n "$(git status --porcelain)" ]; then \
        git commit -m "chore: auto-sync from terraform [skip ci]" && \
        git push origin main; \
      else \
        echo "No changes to commit"; \
      fi
    EOT
  }
}
