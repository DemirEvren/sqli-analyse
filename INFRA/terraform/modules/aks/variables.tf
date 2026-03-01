variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
}

variable "cluster_role" {
  description = "Role of this cluster: 'app' (shelfware workloads + monitoring) or 'loadtest' (Locust)."
  type        = string
  default     = "app"

  validation {
    condition     = contains(["app", "loadtest"], var.cluster_role)
    error_message = "cluster_role must be 'app' or 'loadtest'."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "subnet_id" {
  description = "Resource ID of the subnet where AKS nodes will be placed."
  type        = string
}

variable "system_node_count" {
  description = "Fixed node count for the system node pool."
  type        = number
  default     = 1
}

variable "system_node_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "user_node_min" {
  description = "Minimum node count for the user node pool (autoscaling)."
  type        = number
  default     = 2
}

variable "user_node_max" {
  description = "Maximum node count for the user node pool."
  type        = number
  default     = 5
}

variable "user_node_vm_size" {
  type    = string
  default = "Standard_D4s_v3"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes ClusterIP services (must not overlap VNet or subnet CIDRs)."
  type        = string
  default     = "10.100.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for the DNS service (must be inside service_cidr)."
  type        = string
  default     = "10.100.0.10"
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID. Leave empty to skip OMS agent."
  type        = string
  default     = ""
}

variable "acr_id" {
  description = "Azure Container Registry resource ID. Leave empty to skip AcrPull role assignment."
  type        = string
  default     = ""
}

variable "aks_admin_group_id" {
  description = "Azure AD group object ID that gets AKS cluster admin rights."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
