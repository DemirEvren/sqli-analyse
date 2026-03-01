variable "prefix" {
  description = "Prefix applied to all resource names in this module."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "subnet_app_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "subnet_loadtest_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "subnet_pe_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "tags" {
  type    = map(string)
  default = {}
}
