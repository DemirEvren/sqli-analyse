# ─── Bootstrap: Remote State Backend ─────────────────────────────────────────
#
# Run this ONCE before anything else. It creates the Azure resources that will
# hold the Terraform state file for the main deployment.
#
# Usage:
#   cd INFRA/terraform/bootstrap
#   az login
#   terraform init
#   terraform apply
#
# After apply, copy the outputs into the backend block of ../main.tf
# (or set them as environment variables TF_BACKEND_* – see ../README.md)
#
# Multi-cloud note:
#   Azure  → Azure Blob Storage  (blob leasing = built-in state locking, no extra resource needed)
#   AWS    → S3 bucket + DynamoDB table (see commented block below)
#   GCP    → GCS bucket (object versioning + uniform bucket-level access)
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  # Auth: az login  (interactive)  OR  ARM_* environment variables  OR  service principal in CI
  # subscription_id = var.subscription_id  # uncomment to pin
}

# ─── Uniqueness suffix ────────────────────────────────────────────────────────
# Storage account names must be globally unique and ≤24 chars alphanumeric.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  suffix = lower(random_id.suffix.hex) # 8 hex chars
}

# ─── Resource Group (pre-created by admin) ────────────────────────────────────
# The admin creates this RG and assigns the deployer:
#   • Storage Account Contributor (17d1049b-…) — manage storage account
#   • Locks Contributor            (28bf596f-…) — set CanNotDelete lock
data "azurerm_resource_group" "tfstate" {
  name = var.resource_group_name
}

# ─── Storage Account ──────────────────────────────────────────────────────────
# Blob Storage is the Azure equivalent of an S3 bucket for Terraform state.
# State locking is provided natively via blob leasing — no separate lock table needed.
resource "azurerm_storage_account" "tfstate" {
  name                = "tfstate${var.project_short}${local.suffix}"
  resource_group_name = data.azurerm_resource_group.tfstate.name
  location            = data.azurerm_resource_group.tfstate.location

  account_tier             = "Standard"
  account_replication_type = "ZRS" # Zone-redundant: survives AZ outage

  # Security
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = true

  # Prevent accidental deletion of state
  blob_properties {
    versioning_enabled = true # Roll back to previous state version if needed

    delete_retention_policy {
      days = 90
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = {
    managed-by  = "terraform-bootstrap"
    environment = "shared"
    project     = var.project
  }
}

# ─── Blob Container ───────────────────────────────────────────────────────────
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

# ─── Prevent accidental deletion ─────────────────────────────────────────────
resource "azurerm_management_lock" "tfstate_storage" {
  name       = "protect-tfstate-storage"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Terraform state files are stored here. Deleting this account would destroy all state."
}

# ─── Optional: Azure AD Service Principal for CI/CD ──────────────────────────
# Uncomment if you want Terraform to also create the SP used by GitHub Actions.
#
# resource "azurerm_user_assigned_identity" "terraform_ci" {
#   name                = "${var.project}-terraform-ci"
#   resource_group_name = azurerm_resource_group.tfstate.name
#   location            = azurerm_resource_group.tfstate.location
# }
#
# # Give the CI identity Contributor on the subscription (adjust scope as needed)
# resource "azurerm_role_assignment" "terraform_ci_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Contributor"
#   principal_id         = azurerm_user_assigned_identity.terraform_ci.principal_id
# }

# ─────────────────────────────────────────────────────────────────────────────
# AWS equivalent (for reference when extending to AWS):
# ─────────────────────────────────────────────────────────────────────────────
# provider "aws" { region = var.aws_region }
#
# resource "aws_s3_bucket" "tfstate" {
#   bucket = "tfstate-${var.project}-${local.suffix}"
#   tags   = { managed-by = "terraform-bootstrap" }
# }
# resource "aws_s3_bucket_versioning" "tfstate" {
#   bucket = aws_s3_bucket.tfstate.id
#   versioning_configuration { status = "Enabled" }
# }
# resource "aws_dynamodb_table" "tfstate_lock" {
#   name         = "tfstate-lock-${var.project}"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#   attribute { name = "LockID" type = "S" }
# }
#
# ─────────────────────────────────────────────────────────────────────────────
# GCP equivalent:
# ─────────────────────────────────────────────────────────────────────────────
# provider "google" { project = var.gcp_project; region = var.gcp_region }
#
# resource "google_storage_bucket" "tfstate" {
#   name                        = "tfstate-${var.project}-${local.suffix}"
#   location                    = var.gcp_region
#   uniform_bucket_level_access = true
#   versioning { enabled = true }
# }
