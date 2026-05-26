output "frontdoor_fqdn" {
  value       = azurerm_cdn_frontdoor_endpoint.fd.host_name
  description = "Azure Front Door FQDN — use this as the base URL for the app"
}

output "redirect_uri" {
  value       = "https://${azurerm_cdn_frontdoor_endpoint.fd.host_name}/auth/callback"
  description = "Add this URI to your Entra app registration redirect URIs"
}

output "agw_fqdn_cae" {
  value = local.agw_fqdn_cae
}

output "agw_fqdn_wus2" {
  value = local.agw_fqdn_wus2
}

output "mysql_cae_fqdn" {
  value       = local.mysql_cae_fqdn
  description = "Canada East MySQL primary — both app VMs write here"
}
