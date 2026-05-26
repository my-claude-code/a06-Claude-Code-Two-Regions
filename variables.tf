variable "subscription_id" {
  description = "Azure subscription ID — provide in terraform.tfvars (gitignored)"
  type        = string
}

variable "entra_client_secret" {
  description = "Microsoft Entra app client secret — provide in terraform.tfvars (gitignored)"
  type        = string
  sensitive   = true
}

variable "entra_tenant_id" {
  description = "Microsoft Entra tenant ID — provide in terraform.tfvars (gitignored)"
  type        = string
}

variable "entra_client_id" {
  description = "Microsoft Entra app client ID"
  type        = string
  default     = "1cc4b858-20ae-43da-ae84-506eeb8851c5"
}

variable "flask_secret_key" {
  description = "Flask secret key"
  type        = string
  default     = "f7596fe3803e011564f5ff8de4a96d218ae6a1ed0d83b0d712974ac9e8d17752"
}

variable "db_admin_login" {
  description = "MySQL Flexible Server administrator login"
  type        = string
  default     = "mysqladmin"
}

variable "db_admin_password" {
  description = "MySQL Flexible Server administrator password"
  type        = string
  default     = "AdminPass123!"
}

variable "mysql_server_name_prefix" {
  description = "Prefix for MySQL Flexible Server names — must be globally unique in Azure"
  type        = string
  default     = "mysql-flask-notes-ivansto"
}

variable "agw_dns_label_cae" {
  description = "DNS label for the Canada East Application Gateway public IP"
  type        = string
  default     = "agw-flask-notes-ivansto-cae"
}

variable "agw_dns_label_wus2" {
  description = "DNS label for the West US 2 Application Gateway public IP"
  type        = string
  default     = "agw-flask-notes-ivansto-wus2"
}

variable "frontdoor_endpoint_name" {
  description = "Azure Front Door endpoint name"
  type        = string
  default     = "flask-notes-ivansto"
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "admin_username" {
  description = "VM admin username"
  type        = string
  default     = "ivansto"
}

variable "admin_password" {
  description = "VM admin password"
  type        = string
  default     = "ClaudeCode2023!"
}
