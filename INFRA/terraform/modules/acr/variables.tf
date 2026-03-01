variable "name" {
  description = "ACR name (globally unique, 5-50 lowercase alphanumeric, no dashes)."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  type    = string
  default = "Premium"
}

variable "secondary_location" {
  type    = string
  default = "northeurope"
}

variable "geo_replication_enabled" {
  type    = bool
  default = false
}

variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
