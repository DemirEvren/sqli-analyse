provider "azurerm" {
  features {
    resource_group {
      # Don't let Terraform destroy a non-empty resource group
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }

  subscription_id = var.azure_subscription_id
  # tenant_id       = var.azure_tenant_id  # uncomment for multi-tenant

  # Auth (choose one — see README):
  #  1. az login (interactive, local dev)
  #  2. ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID env vars (CI)
  #  3. Managed Identity (GitHub OIDC — recommended for production CI)
}

provider "azuread" {
  # tenant_id = var.azure_tenant_id  # defaults to subscription tenant
}

# ─── AKS providers — configured after clusters exist ─────────────────────────
# These are aliased so the app-cluster and loadtest-cluster can be addressed
# independently in the same Terraform run.
#
# ⚠ TWO-STAGE APPLY — IMPORTANT
# On a completely fresh workspace the kubernetes/helm providers cannot connect
# because the AKS clusters do not exist yet.  Use the staged apply pattern:
#
#   Stage 1 — create Azure infra only:
#     terraform apply -target=module.aks_app -target=module.aks_loadtest \
#                     -target=module.networking \
#                     -target=module.monitoring -target=data.azurerm_resource_group.main
#
#   Stage 2 — create Kubernetes resources (providers now have valid endpoints):
#     terraform apply
#
# The bootstrap-aks.sh script handles stages 1 + 2 automatically when called
# from CI (see GitHub Actions workflow).
#
# `try()` with safe defaults prevents plan-time errors when state is empty.

locals {
  _app_kube_config = try(module.aks_app.kube_admin_config, {
    host                   = ""
    client_certificate     = ""
    client_key             = ""
    cluster_ca_certificate = ""
  })

  _loadtest_kube_config = try(module.aks_loadtest.kube_admin_config, {
    host                   = ""
    client_certificate     = ""
    client_key             = ""
    cluster_ca_certificate = ""
  })
}

provider "kubernetes" {
  alias                  = "app"
  host                   = local._app_kube_config.host
  client_certificate     = local._app_kube_config.client_certificate != "" ? base64decode(local._app_kube_config.client_certificate) : ""
  client_key             = local._app_kube_config.client_key != "" ? base64decode(local._app_kube_config.client_key) : ""
  cluster_ca_certificate = local._app_kube_config.cluster_ca_certificate != "" ? base64decode(local._app_kube_config.cluster_ca_certificate) : ""
}

provider "kubernetes" {
  alias                  = "loadtest"
  host                   = local._loadtest_kube_config.host
  client_certificate     = local._loadtest_kube_config.client_certificate != "" ? base64decode(local._loadtest_kube_config.client_certificate) : ""
  client_key             = local._loadtest_kube_config.client_key != "" ? base64decode(local._loadtest_kube_config.client_key) : ""
  cluster_ca_certificate = local._loadtest_kube_config.cluster_ca_certificate != "" ? base64decode(local._loadtest_kube_config.cluster_ca_certificate) : ""
}

provider "helm" {
  alias = "app"
  kubernetes {
    host                   = local._app_kube_config.host
    client_certificate     = local._app_kube_config.client_certificate != "" ? base64decode(local._app_kube_config.client_certificate) : ""
    client_key             = local._app_kube_config.client_key != "" ? base64decode(local._app_kube_config.client_key) : ""
    cluster_ca_certificate = local._app_kube_config.cluster_ca_certificate != "" ? base64decode(local._app_kube_config.cluster_ca_certificate) : ""
  }
}

provider "helm" {
  alias = "loadtest"
  kubernetes {
    host                   = local._loadtest_kube_config.host
    client_certificate     = local._loadtest_kube_config.client_certificate != "" ? base64decode(local._loadtest_kube_config.client_certificate) : ""
    client_key             = local._loadtest_kube_config.client_key != "" ? base64decode(local._loadtest_kube_config.client_key) : ""
    cluster_ca_certificate = local._loadtest_kube_config.cluster_ca_certificate != "" ? base64decode(local._loadtest_kube_config.cluster_ca_certificate) : ""
  }
}

# ─── AWS provider (future) ────────────────────────────────────────────────────
# provider "aws" {
#   region = var.aws_region
#   # Auth: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY  or  OIDC role assumption
# }

# ─── GCP provider (future) ────────────────────────────────────────────────────
# provider "google" {
#   project = var.gcp_project_id
#   region  = var.gcp_region
#   # Auth: gcloud auth application-default login  or  GOOGLE_CREDENTIALS env var
# }
