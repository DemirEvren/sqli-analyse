# ─── Cloud selection ─────────────────────────────────────────────────────────

variable "cloud_provider" {
  description = "Active cloud provider. Determines which resources/modules are used. Supported: azure, aws, gcp."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "aws", "gcp"], var.cloud_provider)
    error_message = "cloud_provider must be one of: azure, aws, gcp."
  }
}

# ─── Global ───────────────────────────────────────────────────────────────────

variable "project" {
  description = "Project name used as a prefix/tag in all resource names."
  type        = string
  default     = "sqli"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod). Used in resource names and tags."
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# ─── Azure ────────────────────────────────────────────────────────────────────

variable "azure_subscription_id" {
  description = "Azure Subscription ID. Can also be set via ARM_SUBSCRIPTION_ID env var."
  type        = string
  default     = ""
  sensitive   = false # IDs are not secret; credentials are passed via env
}

variable "azure_location" {
  description = "Primary Azure region. Used as fallback; the pre-created resource group's location takes precedence."
  type        = string
  default     = "westeurope"
}

variable "azure_resource_group_name" {
  description = "Name of the pre-created Azure resource group. Must exist before running Terraform. Leave empty to use auto-generated name 'rg-<project>-<environment>' (the admin must still pre-create it)."
  type        = string
  default     = ""
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vnet_address_space" {
  description = "Address space for the shared VNet."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_app_cidr" {
  description = "CIDR block for the app-cluster AKS node pool subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_loadtest_cidr" {
  description = "CIDR block for the loadtest-cluster AKS node pool subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_private_endpoints_cidr" {
  description = "CIDR block for private endpoints (ACR, Key Vault, etc.)."
  type        = string
  default     = "10.0.3.0/24"
}

# ─── AKS — App Cluster ────────────────────────────────────────────────────────

variable "app_cluster_name" {
  description = "AKS cluster name for the shelfware application."
  type        = string
  default     = "shelfware-app"
}

variable "app_cluster_kubernetes_version" {
  description = "Kubernetes version for the app cluster. Use 'latest' or a specific version like '1.30'."
  type        = string
  default     = "1.30"
}

variable "app_cluster_system_node_count" {
  description = "Number of nodes in the system node pool (coreDNS, konnectivity, etc.)."
  type        = number
  default     = 1
}

variable "app_cluster_system_node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v3" # 2 vCPU, 8 GiB — matches k3d agent nodes (~8 vCPU/22 GiB on k3d)
}

variable "app_cluster_user_node_min" {
  description = "Minimum nodes in the user node pool (cluster autoscaler)."
  type        = number
  default     = 2
}

variable "app_cluster_user_node_max" {
  description = "Maximum nodes in the user node pool."
  type        = number
  default     = 5
}

variable "app_cluster_user_node_vm_size" {
  description = "VM size for the user node pool."
  type        = string
  default     = "Standard_D4s_v3" # 4 vCPU, 16 GiB
}

# ─── AKS — Loadtest Cluster ───────────────────────────────────────────────────

variable "loadtest_cluster_name" {
  description = "AKS cluster name for the Locust load-test workloads."
  type        = string
  default     = "shelfware-loadtest"
}

variable "loadtest_cluster_kubernetes_version" {
  description = "Kubernetes version for the loadtest cluster."
  type        = string
  default     = "1.30"
}

variable "loadtest_cluster_node_count" {
  description = "Number of nodes in the loadtest cluster node pool."
  type        = number
  default     = 1
}

variable "loadtest_cluster_node_vm_size" {
  description = "VM size for the loadtest cluster node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

# ─── Application secrets (passed through to Kubernetes secrets) ───────────────

variable "postgres_password" {
  description = "PostgreSQL password for the shelfware database. Pass via TF_VAR_postgres_password env var."
  type        = string
  sensitive   = true
  # No default — forces the deployer to set it explicitly via env var or secrets.env
}

variable "jwt_secret" {
  description = "JWT signing secret for the shelfware backend. Pass via TF_VAR_jwt_secret env var."
  type        = string
  sensitive   = true
  # No default — forces the deployer to set it explicitly
}

variable "github_token" {
  description = "GitHub PAT (packages:read) used by Kubernetes to pull images from ghcr.io. Pass via TF_VAR_github_token env var."
  type        = string
  sensitive   = true
  # No default — forces the deployer to set it explicitly
}

variable "github_username" {
  description = "GitHub username associated with the PAT."
  type        = string
  default     = "DemirEvren"
}

# ─── ArgoCD ───────────────────────────────────────────────────────────────────

variable "argocd_repo_url" {
  description = "Git repository URL that ArgoCD tracks."
  type        = string
  default     = "https://github.com/DemirEvren/sqli-analyse.git"
}

variable "argocd_target_revision" {
  description = "Branch or tag ArgoCD syncs from."
  type        = string
  default     = "main"
}

# ─── Monitoring ───────────────────────────────────────────────────────────────

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics Workspace."
  type        = number
  default     = 30
}

variable "prometheus_retention_days" {
  description = "Prometheus data retention in days (applies to in-cluster Prometheus)."
  type        = number
  default     = 30
}

# ─── DNS (Ingress) ────────────────────────────────────────────────────────────

variable "dns_zone_name" {
  description = "Azure DNS zone name. Leave empty to use nip.io dynamic DNS instead."
  type        = string
  default     = "" # e.g. "shelfware.example.com"
}

# ─── AWS (future) ─────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region (used when cloud_provider = aws)."
  type        = string
  default     = "eu-west-1"
}

variable "aws_eks_cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.30"
}

# ─── GCP (future) ─────────────────────────────────────────────────────────────

variable "gcp_project_id" {
  description = "GCP project ID (used when cloud_provider = gcp)."
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region (used when cloud_provider = gcp)."
  type        = string
  default     = "europe-west1"
}
