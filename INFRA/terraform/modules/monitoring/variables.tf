variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 30
}

variable "managed_prometheus_enabled" {
  description = "Create an Azure Monitor Workspace (managed Prometheus). Default false — we use in-cluster Prometheus."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
