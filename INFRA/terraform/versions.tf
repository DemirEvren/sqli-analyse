terraform {
  required_version = ">= 1.7"

  # ─── Azure Blob remote state ─────────────────────────────────────────────
  # Populate these values from the bootstrap outputs, either hard-coded here
  # or (recommended for teams/CI) via a backend config file:
  #
  #   terraform init -backend-config=backend.conf
  #
  # where backend.conf contains:
  #   resource_group_name  = "rg-shelfware-tfstate"
  #   storage_account_name = "<output from bootstrap>"
  #   container_name       = "tfstate"
  #   key                  = "shelfware/terraform.tfstate"
  #
  # State locking: Azure Blob Storage uses native blob leasing.
  # When one user runs `terraform apply`, the blob is leased (locked).
  # Any concurrent run gets: "Error: Failed to lock state: state blob is already locked"
  # — exactly like DynamoDB locking on AWS.
  #
  # AWS equivalent backend:
  #   backend "s3" {
  #     bucket         = "<s3-bucket-from-bootstrap>"
  #     key            = "shelfware/terraform.tfstate"
  #     region         = "eu-west-1"
  #     dynamodb_table = "<dynamo-table-from-bootstrap>"
  #     encrypt        = true
  #   }
  #
  # GCP equivalent backend:
  #   backend "gcs" {
  #     bucket = "<gcs-bucket-from-bootstrap>"
  #     prefix = "shelfware/terraform"
  #   }
  backend "azurerm" {
    resource_group_name  = "rg-shelfware-tfstate" # override with -backend-config
    storage_account_name = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
    container_name       = "tfstate"
    key                  = "shelfware/terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    # ── Future: uncomment when adding AWS support ──────────────────────────
    # aws = {
    #   source  = "hashicorp/aws"
    #   version = "~> 5.0"
    # }

    # ── Future: uncomment when adding GCP support ──────────────────────────
    # google = {
    #   source  = "hashicorp/google"
    #   version = "~> 5.0"
    # }
  }
}
