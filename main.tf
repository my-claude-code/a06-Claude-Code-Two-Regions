terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  prefix        = "flask-notes"
  db_name       = "flask_notes"

  mysql_cae_fqdn  = "${var.mysql_server_name_prefix}-cae.mysql.database.azure.com"
  mysql_wus2_fqdn = "${var.mysql_server_name_prefix}-wus2.mysql.database.azure.com"
  agw_fqdn_cae    = "${var.agw_dns_label_cae}.canadaeast.cloudapp.azure.com"
  agw_fqdn_wus2   = "${var.agw_dns_label_wus2}.westus2.cloudapp.azure.com"
}

# ── Global Resource Group + Front Door ──────────────────────────────────────

resource "azurerm_resource_group" "rg_global" {
  name     = "rg-${local.prefix}-global"
  location = "Canada East"
}

resource "azurerm_cdn_frontdoor_profile" "fd" {
  name                = "afd-${local.prefix}-ivansto"
  resource_group_name = azurerm_resource_group.rg_global.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "fd" {
  name                     = var.frontdoor_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
}

# ── Canada East — Resource Group & Network ───────────────────────────────────

resource "azurerm_resource_group" "rg_cae" {
  name     = "rg-${local.prefix}-cae"
  location = "Canada East"
}

resource "time_sleep" "rg_cae_ready" {
  depends_on      = [azurerm_resource_group.rg_cae]
  create_duration = "30s"
}

resource "azurerm_virtual_network" "vnet_cae" {
  name                = "vnet-${local.prefix}-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name
  address_space       = ["10.0.0.0/16"]
  depends_on          = [time_sleep.rg_cae_ready]
}

resource "time_sleep" "vnet_cae_ready" {
  depends_on      = [azurerm_virtual_network.vnet_cae]
  create_duration = "30s"
}

resource "azurerm_subnet" "agw_cae" {
  name                 = "subnet-agw"
  resource_group_name  = azurerm_resource_group.rg_cae.name
  virtual_network_name = azurerm_virtual_network.vnet_cae.name
  address_prefixes     = ["10.0.0.0/24"]
  depends_on           = [time_sleep.vnet_cae_ready]
}

resource "azurerm_subnet" "web_cae" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.rg_cae.name
  virtual_network_name = azurerm_virtual_network.vnet_cae.name
  address_prefixes     = ["10.0.1.0/24"]
  depends_on           = [time_sleep.vnet_cae_ready]
}

resource "azurerm_subnet" "app_cae" {
  name                 = "subnet-app"
  resource_group_name  = azurerm_resource_group.rg_cae.name
  virtual_network_name = azurerm_virtual_network.vnet_cae.name
  address_prefixes     = ["10.0.2.0/24"]
  depends_on           = [time_sleep.vnet_cae_ready]
}

resource "azurerm_network_security_group" "agw_cae" {
  name                = "nsg-agw-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name
  depends_on          = [time_sleep.vnet_cae_ready]
  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "web_cae" {
  name                = "nsg-web-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name
  depends_on          = [time_sleep.vnet_cae_ready]
  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "app_cae" {
  name                = "nsg-app-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name
  depends_on          = [time_sleep.vnet_cae_ready]
  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "agw_cae" {
  subnet_id                 = azurerm_subnet.agw_cae.id
  network_security_group_id = azurerm_network_security_group.agw_cae.id
}

resource "azurerm_subnet_network_security_group_association" "web_cae" {
  subnet_id                 = azurerm_subnet.web_cae.id
  network_security_group_id = azurerm_network_security_group.web_cae.id
}

resource "azurerm_subnet_network_security_group_association" "app_cae" {
  subnet_id                 = azurerm_subnet.app_cae.id
  network_security_group_id = azurerm_network_security_group.app_cae.id
}

resource "azurerm_public_ip" "nat_cae" {
  name                = "pip-nat-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.rg_cae_ready]
}

resource "azurerm_nat_gateway" "nat_cae" {
  name                = "nat-${local.prefix}-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name
  sku_name            = "Standard"
  depends_on          = [time_sleep.rg_cae_ready]
}

resource "azurerm_nat_gateway_public_ip_association" "nat_cae" {
  nat_gateway_id       = azurerm_nat_gateway.nat_cae.id
  public_ip_address_id = azurerm_public_ip.nat_cae.id
}

resource "azurerm_subnet_nat_gateway_association" "web_cae" {
  subnet_id      = azurerm_subnet.web_cae.id
  nat_gateway_id = azurerm_nat_gateway.nat_cae.id
}

resource "azurerm_subnet_nat_gateway_association" "app_cae" {
  subnet_id      = azurerm_subnet.app_cae.id
  nat_gateway_id = azurerm_nat_gateway.nat_cae.id
}

# ── Canada East — Application Gateway ────────────────────────────────────────

resource "azurerm_public_ip" "agw_cae" {
  name                = "pip-agw-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.agw_dns_label_cae
  depends_on          = [time_sleep.rg_cae_ready]
}

resource "azurerm_application_gateway" "agw_cae" {
  name                = "agw-${local.prefix}-cae"
  resource_group_name = azurerm_resource_group.rg_cae.name
  location            = azurerm_resource_group.rg_cae.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "agw-ip-config"
    subnet_id = azurerm_subnet.agw_cae.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "agw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.agw_cae.id
  }

  backend_address_pool { name = "web-backend-pool" }

  backend_http_settings {
    name                                = "http-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 60
    probe_name                          = "http-probe"
    pick_host_name_from_backend_address = true
  }

  probe {
    name                                      = "http-probe"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 5
    pick_host_name_from_backend_http_settings = true
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "agw-frontend-ip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "http-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "web-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 10
  }
}

# ── Canada East — MySQL Flexible Server (primary) ────────────────────────────

resource "azurerm_mysql_flexible_server" "mysql_cae" {
  name                   = "${var.mysql_server_name_prefix}-cae"
  resource_group_name    = azurerm_resource_group.rg_cae.name
  location               = azurerm_resource_group.rg_cae.location
  administrator_login    = var.db_admin_login
  administrator_password = var.db_admin_password
  sku_name               = "B_Standard_B1ms"
  version                = "8.0.21"

  storage {
    size_gb = 20
  }

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  depends_on                   = [time_sleep.rg_cae_ready]
}

resource "azurerm_mysql_flexible_server_firewall_rule" "mysql_cae_allow_all" {
  name                = "allow-all"
  resource_group_name = azurerm_resource_group.rg_cae.name
  server_name         = azurerm_mysql_flexible_server.mysql_cae.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

resource "azurerm_mysql_flexible_server_configuration" "ssl_cae" {
  name                = "require_secure_transport"
  resource_group_name = azurerm_resource_group.rg_cae.name
  server_name         = azurerm_mysql_flexible_server.mysql_cae.name
  value               = "OFF"
}

resource "azurerm_mysql_flexible_database" "flask_notes" {
  name                = local.db_name
  resource_group_name = azurerm_resource_group.rg_cae.name
  server_name         = azurerm_mysql_flexible_server.mysql_cae.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# ── Canada East — App VM ─────────────────────────────────────────────────────

resource "azurerm_network_interface" "app_cae" {
  name                = "nic-app-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name

  ip_configuration {
    name                          = "ipconfig-app"
    subnet_id                     = azurerm_subnet.app_cae.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "app_cae" {
  name                            = "vm-app-cae"
  location                        = azurerm_resource_group.rg_cae.location
  resource_group_name             = azurerm_resource_group.rg_cae.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.app_cae.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/app-setup.sh", {
    entra_client_id     = var.entra_client_id
    entra_client_secret = var.entra_client_secret
    entra_tenant_id     = var.entra_tenant_id
    flask_secret_key    = var.flask_secret_key
    frontdoor_fqdn      = azurerm_cdn_frontdoor_endpoint.fd.host_name
    mysql_cae_fqdn      = local.mysql_cae_fqdn
    db_name             = local.db_name
    db_admin_login      = var.db_admin_login
    db_admin_password   = var.db_admin_password
  }))

  depends_on = [
    azurerm_mysql_flexible_server_configuration.ssl_cae,
    azurerm_mysql_flexible_database.flask_notes,
    azurerm_subnet_nat_gateway_association.app_cae,
  ]
}

# ── Canada East — Web VM ─────────────────────────────────────────────────────

resource "azurerm_network_interface" "web_cae" {
  name                = "nic-web-cae"
  location            = azurerm_resource_group.rg_cae.location
  resource_group_name = azurerm_resource_group.rg_cae.name

  ip_configuration {
    name                          = "ipconfig-web"
    subnet_id                     = azurerm_subnet.web_cae.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "web_cae" {
  name                            = "vm-web-cae"
  location                        = azurerm_resource_group.rg_cae.location
  resource_group_name             = azurerm_resource_group.rg_cae.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.web_cae.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/web-setup.sh", {
    app_private_ip = azurerm_network_interface.app_cae.private_ip_address
  }))

  depends_on = [azurerm_subnet_nat_gateway_association.web_cae]
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "web_cae" {
  network_interface_id    = azurerm_network_interface.web_cae.id
  ip_configuration_name   = "ipconfig-web"
  backend_address_pool_id = one([for bp in azurerm_application_gateway.agw_cae.backend_address_pool : bp.id])
}

# ── West US 2 — Resource Group & Network ─────────────────────────────────────

resource "azurerm_resource_group" "rg_wus2" {
  name     = "rg-${local.prefix}-wus2"
  location = "West US 2"
}

resource "time_sleep" "rg_wus2_ready" {
  depends_on      = [azurerm_resource_group.rg_wus2]
  create_duration = "30s"
}

resource "azurerm_virtual_network" "vnet_wus2" {
  name                = "vnet-${local.prefix}-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name
  address_space       = ["10.1.0.0/16"]
  depends_on          = [time_sleep.rg_wus2_ready]
}

resource "time_sleep" "vnet_wus2_ready" {
  depends_on      = [azurerm_virtual_network.vnet_wus2]
  create_duration = "30s"
}

resource "azurerm_subnet" "agw_wus2" {
  name                 = "subnet-agw"
  resource_group_name  = azurerm_resource_group.rg_wus2.name
  virtual_network_name = azurerm_virtual_network.vnet_wus2.name
  address_prefixes     = ["10.1.0.0/24"]
  depends_on           = [time_sleep.vnet_wus2_ready]
}

resource "azurerm_subnet" "web_wus2" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.rg_wus2.name
  virtual_network_name = azurerm_virtual_network.vnet_wus2.name
  address_prefixes     = ["10.1.1.0/24"]
  depends_on           = [time_sleep.vnet_wus2_ready]
}

resource "azurerm_subnet" "app_wus2" {
  name                 = "subnet-app"
  resource_group_name  = azurerm_resource_group.rg_wus2.name
  virtual_network_name = azurerm_virtual_network.vnet_wus2.name
  address_prefixes     = ["10.1.2.0/24"]
  depends_on           = [time_sleep.vnet_wus2_ready]
}

resource "azurerm_network_security_group" "agw_wus2" {
  name                = "nsg-agw-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name
  depends_on          = [time_sleep.vnet_wus2_ready]
  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "web_wus2" {
  name                = "nsg-web-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name
  depends_on          = [time_sleep.vnet_wus2_ready]
  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "app_wus2" {
  name                = "nsg-app-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name
  depends_on          = [time_sleep.vnet_wus2_ready]
  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "agw_wus2" {
  subnet_id                 = azurerm_subnet.agw_wus2.id
  network_security_group_id = azurerm_network_security_group.agw_wus2.id
}

resource "azurerm_subnet_network_security_group_association" "web_wus2" {
  subnet_id                 = azurerm_subnet.web_wus2.id
  network_security_group_id = azurerm_network_security_group.web_wus2.id
}

resource "azurerm_subnet_network_security_group_association" "app_wus2" {
  subnet_id                 = azurerm_subnet.app_wus2.id
  network_security_group_id = azurerm_network_security_group.app_wus2.id
}

resource "azurerm_public_ip" "nat_wus2" {
  name                = "pip-nat-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.rg_wus2_ready]
}

resource "azurerm_nat_gateway" "nat_wus2" {
  name                = "nat-${local.prefix}-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name
  sku_name            = "Standard"
  depends_on          = [time_sleep.rg_wus2_ready]
}

resource "azurerm_nat_gateway_public_ip_association" "nat_wus2" {
  nat_gateway_id       = azurerm_nat_gateway.nat_wus2.id
  public_ip_address_id = azurerm_public_ip.nat_wus2.id
}

resource "azurerm_subnet_nat_gateway_association" "web_wus2" {
  subnet_id      = azurerm_subnet.web_wus2.id
  nat_gateway_id = azurerm_nat_gateway.nat_wus2.id
}

resource "azurerm_subnet_nat_gateway_association" "app_wus2" {
  subnet_id      = azurerm_subnet.app_wus2.id
  nat_gateway_id = azurerm_nat_gateway.nat_wus2.id
}

# ── West US 2 — Application Gateway ──────────────────────────────────────────

resource "azurerm_public_ip" "agw_wus2" {
  name                = "pip-agw-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.agw_dns_label_wus2
  depends_on          = [time_sleep.rg_wus2_ready]
}

resource "azurerm_application_gateway" "agw_wus2" {
  name                = "agw-${local.prefix}-wus2"
  resource_group_name = azurerm_resource_group.rg_wus2.name
  location            = azurerm_resource_group.rg_wus2.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "agw-ip-config"
    subnet_id = azurerm_subnet.agw_wus2.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "agw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.agw_wus2.id
  }

  backend_address_pool { name = "web-backend-pool" }

  backend_http_settings {
    name                                = "http-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 60
    probe_name                          = "http-probe"
    pick_host_name_from_backend_address = true
  }

  probe {
    name                                      = "http-probe"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 5
    pick_host_name_from_backend_http_settings = true
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "agw-frontend-ip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "http-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "web-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 10
  }
}

# ── West US 2 — MySQL Flexible Server (read replica of Canada East) ───────────

resource "azurerm_mysql_flexible_server" "mysql_wus2" {
  name                   = "${var.mysql_server_name_prefix}-wus2"
  resource_group_name    = azurerm_resource_group.rg_wus2.name
  location               = azurerm_resource_group.rg_wus2.location
  administrator_login    = var.db_admin_login
  administrator_password = var.db_admin_password
  sku_name               = "B_Standard_B1ms"
  version                = "8.0.21"

  storage {
    size_gb = 20
  }

  backup_retention_days        = 1
  geo_redundant_backup_enabled = false
  depends_on                   = [time_sleep.rg_wus2_ready]
}

resource "azurerm_mysql_flexible_server_firewall_rule" "mysql_wus2_allow_all" {
  name                = "allow-all"
  resource_group_name = azurerm_resource_group.rg_wus2.name
  server_name         = azurerm_mysql_flexible_server.mysql_wus2.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

resource "azurerm_mysql_flexible_server_configuration" "ssl_wus2" {
  name                = "require_secure_transport"
  resource_group_name = azurerm_resource_group.rg_wus2.name
  server_name         = azurerm_mysql_flexible_server.mysql_wus2.name
  value               = "OFF"
}

# ── West US 2 — App VM ───────────────────────────────────────────────────────

resource "azurerm_network_interface" "app_wus2" {
  name                = "nic-app-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name

  ip_configuration {
    name                          = "ipconfig-app"
    subnet_id                     = azurerm_subnet.app_wus2.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "app_wus2" {
  name                            = "vm-app-wus2"
  location                        = azurerm_resource_group.rg_wus2.location
  resource_group_name             = azurerm_resource_group.rg_wus2.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.app_wus2.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Both regions write to the Canada East primary MySQL
  custom_data = base64encode(templatefile("${path.module}/scripts/app-setup.sh", {
    entra_client_id     = var.entra_client_id
    entra_client_secret = var.entra_client_secret
    entra_tenant_id     = var.entra_tenant_id
    flask_secret_key    = var.flask_secret_key
    frontdoor_fqdn      = azurerm_cdn_frontdoor_endpoint.fd.host_name
    mysql_cae_fqdn      = local.mysql_cae_fqdn
    db_name             = local.db_name
    db_admin_login      = var.db_admin_login
    db_admin_password   = var.db_admin_password
  }))

  depends_on = [
    azurerm_mysql_flexible_server_configuration.ssl_cae,
    azurerm_mysql_flexible_database.flask_notes,
    azurerm_subnet_nat_gateway_association.app_wus2,
  ]
}

# ── West US 2 — Web VM ───────────────────────────────────────────────────────

resource "azurerm_network_interface" "web_wus2" {
  name                = "nic-web-wus2"
  location            = azurerm_resource_group.rg_wus2.location
  resource_group_name = azurerm_resource_group.rg_wus2.name

  ip_configuration {
    name                          = "ipconfig-web"
    subnet_id                     = azurerm_subnet.web_wus2.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "web_wus2" {
  name                            = "vm-web-wus2"
  location                        = azurerm_resource_group.rg_wus2.location
  resource_group_name             = azurerm_resource_group.rg_wus2.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.web_wus2.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/web-setup.sh", {
    app_private_ip = azurerm_network_interface.app_wus2.private_ip_address
  }))

  depends_on = [azurerm_subnet_nat_gateway_association.web_wus2]
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "web_wus2" {
  network_interface_id    = azurerm_network_interface.web_wus2.id
  ip_configuration_name   = "ipconfig-web"
  backend_address_pool_id = one([for bp in azurerm_application_gateway.agw_wus2.backend_address_pool : bp.id])
}

# ── Front Door — Origins & Route (after both AGWs exist) ────────────────────

resource "azurerm_cdn_frontdoor_origin_group" "fd" {
  name                     = "flask-notes-origins"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 0
  }

  health_probe {
    path                = "/"
    protocol            = "Http"
    request_type        = "GET"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_origin" "cae" {
  name                          = "cae-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.fd.id
  enabled                       = true
  host_name                     = azurerm_public_ip.agw_cae.fqdn
  origin_host_header            = azurerm_public_ip.agw_cae.fqdn
  https_port                    = 443
  http_port                     = 80
  priority                      = 1
  weight                        = 500
  certificate_name_check_enabled = false
}

resource "azurerm_cdn_frontdoor_origin" "wus2" {
  name                          = "wus2-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.fd.id
  enabled                       = true
  host_name                     = azurerm_public_ip.agw_wus2.fqdn
  origin_host_header            = azurerm_public_ip.agw_wus2.fqdn
  https_port                    = 443
  http_port                     = 80
  priority                      = 1
  weight                        = 500
  certificate_name_check_enabled = false
}

resource "azurerm_cdn_frontdoor_route" "fd" {
  name                          = "flask-notes-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.fd.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.fd.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.cae.id, azurerm_cdn_frontdoor_origin.wus2.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}
