variable "resource_group_name" {
  description = "Resource group that holds only the Terraform state storage account."
  type        = string
  default     = "rg-shelfware-tfstate"
}

variable "location" {
  description = "Azure region for the state backend resources."
  type        = string
  default     = "westeurope"
}

variable "project" {
  description = "Short project name used in resource names and tags."
  type        = string
  default     = "shelfware"
}

variable "project_short" {
  description = "≤8 chars — used inside the storage account name (globally unique, ≤24 total)."
  type        = string
  default     = "shlf"

  validation {
    condition     = length(var.project_short) <= 8 && can(regex("^[a-z0-9]+$", var.project_short))
    error_message = "project_short must be ≤8 lowercase alphanumeric characters."
  }
}
