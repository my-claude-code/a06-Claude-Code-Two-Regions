# a06 — Two-Region Active-Active Flask Notes App

Flask notes app deployed across two Azure regions with Azure Front Door load balancing and MySQL Flexible Server replication.

---

## Architecture

```
Internet (HTTPS)
      │
      ▼
Azure Front Door (Standard)
  flask-notes-ivansto.azurefd.net
      │
      ├─── 50% ───▶ Application Gateway (Canada East, HTTPS)
      │                    │
      │              Web VM — nginx (Canada East)
      │                    │
      │              App VM — Flask/gunicorn (Canada East)
      │                    │
      │                    ▼
      │             MySQL Flexible Server ◀─── PRIMARY (read/write)
      │             Canada East              │
      │                                      │ replication
      └─── 50% ───▶ Application Gateway (West US 2, HTTPS)
                          │
                    Web VM — nginx (West US 2)
                          │
                    App VM — Flask/gunicorn (West US 2)
                          │
                          └──────────────────▶ MySQL Flexible Server
                                               Canada East (PRIMARY)

                    MySQL Flexible Server ◀─── REPLICA (read-only, DR)
                    West US 2
```

### Why both app VMs write to Canada East MySQL

Azure MySQL Flexible Server managed read replicas require **General Purpose or Business Critical tier** — the Burstable tier (`B_Standard_B1ms`) does not support them. To keep costs low both servers run as independent Burstable instances.

- **Canada East app VM** → writes to Canada East MySQL (local, fast)
- **West US 2 app VM** → writes to Canada East MySQL (cross-region)
- **West US 2 MySQL** → independent standby, same schema, no live replication
- If Canada East fails: point West US 2 app at its local MySQL and run `flask init-db`

To enable Azure-managed replication, upgrade both servers to `GP_Standard_D2ds_v4` and add `create_mode = "Replica"` + `source_server_id` to the West US 2 server.

---

## Components

### Global
| Resource | Name | Purpose |
|---|---|---|
| Resource Group | rg-flask-notes-global | Contains Front Door |
| Front Door Profile | afd-flask-notes-ivansto | Standard SKU, global load balancer |
| Front Door Endpoint | flask-notes-ivansto | Public entry point, `.azurefd.net` FQDN |
| Origin Group | flask-notes-origins | Equal weight (500/500), HTTPS health probes |
| Origins | cae-origin, wus2-origin | Point to each AGW's public IP FQDN |
| Route | flask-notes-route | `/*`, HTTPS forwarding, HTTP→HTTPS redirect |

### Canada East (10.0.0.0/16)
| Resource | Purpose |
|---|---|
| Application Gateway Standard_v2 | TLS termination, routes to web VM |
| Self-signed TLS cert (PFX) | Generated via PowerShell on your machine |
| Web VM (nginx) | Reverse proxy → app VM port 5000 |
| App VM (Flask/gunicorn) | Flask app, connects to Canada East MySQL |
| NAT Gateway | Outbound internet for web and app VMs |
| NSGs (agw, web, app) | All inbound open for testing |
| MySQL Flexible Server B1ms | **Primary** — accepts all reads and writes |

### West US 2 (10.1.0.0/16)
| Resource | Purpose |
|---|---|
| Application Gateway Standard_v2 | TLS termination, routes to web VM |
| Self-signed TLS cert (PFX) | Generated via PowerShell on your machine |
| Web VM (nginx) | Reverse proxy → app VM port 5000 |
| App VM (Flask/gunicorn) | Flask app, connects to Canada East MySQL |
| NAT Gateway | Outbound internet for web and app VMs |
| NSGs (agw, web, app) | All inbound open for testing |
| MySQL Flexible Server B1ms | **Independent standby** — same schema, no managed replication |

---

## Network Layout

```
Canada East VNet — 10.0.0.0/16
  subnet-agw  10.0.0.0/24  — Application Gateway
  subnet-web  10.0.1.0/24  — Web VM (nginx), NAT Gateway
  subnet-app  10.0.2.0/24  — App VM (Flask), NAT Gateway

West US 2 VNet — 10.1.0.0/16
  subnet-agw  10.1.0.0/24  — Application Gateway
  subnet-web  10.1.1.0/24  — Web VM (nginx), NAT Gateway
  subnet-app  10.1.2.0/24  — App VM (Flask), NAT Gateway
```

No VNet peering is needed. MySQL uses public access mode with a firewall rule allowing all IPs (`0.0.0.0–255.255.255.255`). SSL transport is disabled so PyMySQL connects without a client certificate.

---

## Request Flow

1. Browser → `https://flask-notes-ivansto.azurefd.net`
2. Front Door picks a healthy origin (Canada East or West US 2, equal weight)
3. Front Door → AGW on HTTPS port 443 (self-signed cert, check disabled)
4. AGW → Web VM nginx on HTTP port 80
5. nginx → App VM gunicorn on HTTP port 5000
6. Flask app → Canada East MySQL port 3306 (public, over internet)
7. Response travels back the same path

---

## Deployment

### Prerequisites
- Azure CLI logged in (`az login`)
- Terraform installed
- PowerShell available (used to generate self-signed PFX certs locally)

### Steps

```bash
git clone https://github.com/my-claude-code/a06-Claude-Code-Two-Regions.git
cd a06-Claude-Code-Two-Regions

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars and fill in the three required values
```

`terraform.tfvars`:
```hcl
subscription_id     = "your-azure-subscription-id"
entra_client_secret = "your-entra-client-secret"
entra_tenant_id     = "your-entra-tenant-id"
```

```bash
terraform init
terraform apply
```

Total deployment time is roughly **25–35 minutes** — MySQL Flexible Server provisioning (~10 min per server) dominates.

### After apply — required Entra step

```bash
terraform output redirect_uri
```

Copy the output URL and add it to your **Microsoft Entra app registration → Authentication → Redirect URIs**. It will look like:

```
https://flask-notes-ivansto-xxxxxxx.z01.azurefd.net/auth/callback
```

Without this step, Entra will refuse the OAuth callback with AADSTS50011.

---

## Variables

| Variable | Default | Description |
|---|---|---|
| `subscription_id` | — | Azure subscription ID (**required in tfvars**) |
| `entra_client_secret` | — | Entra app client secret (**required in tfvars**) |
| `entra_tenant_id` | — | Entra tenant ID (**required in tfvars**) |
| `entra_client_id` | `1cc4b858-...` | Entra app client ID |
| `flask_secret_key` | `f7596fe3...` | Flask session signing key |
| `db_admin_login` | `mysqladmin` | MySQL admin username |
| `db_admin_password` | `AdminPass123!` | MySQL admin password |
| `mysql_server_name_prefix` | `mysql-flask-notes-ivansto` | Prefix for both MySQL server names |
| `agw_dns_label_cae` | `agw-flask-notes-ivansto-cae` | DNS label for Canada East AGW public IP |
| `agw_dns_label_wus2` | `agw-flask-notes-ivansto-wus2` | DNS label for West US 2 AGW public IP |
| `frontdoor_endpoint_name` | `flask-notes-ivansto` | Front Door endpoint name |
| `vm_size` | `Standard_B2s_v2` | VM size for all four VMs |
| `admin_username` | `ivansto` | VM SSH/login username |
| `admin_password` | `ClaudeCode2023!` | VM password |

---

## Outputs

| Output | Description |
|---|---|
| `frontdoor_fqdn` | Full Front Door hostname — the app's public URL |
| `redirect_uri` | Full redirect URI to add to Entra |
| `agw_fqdn_cae` | Canada East Application Gateway FQDN |
| `agw_fqdn_wus2` | West US 2 Application Gateway FQDN |
| `mysql_cae_fqdn` | Canada East MySQL FQDN (primary) |

---

## Estimated Cost

This setup is expensive — deploy, test, then `terraform destroy`.

| Resource | Est. $/month |
|---|---|
| 2× Application Gateway Standard_v2 | ~$40 |
| Azure Front Door Standard | ~$35 + traffic |
| 4× Standard_B2s_v2 VMs | ~$60 |
| 2× MySQL Flexible Server B1ms | ~$30 |
| 2× NAT Gateways | ~$32 |
| **Total** | **~$200+** |

### Teardown

```bash
terraform destroy
```

---

## DR Failover (manual)

If Canada East goes down:

1. In the Azure Portal, go to the West US 2 MySQL Flexible Server
2. Click **Replication → Promote to independent server**
3. Wait for promotion to complete
4. Update the West US 2 app VM's `/opt/flask-app/.env`:
   ```
   DATABASE_URL=mysql+pymysql://mysqladmin:AdminPass123!@mysql-flask-notes-ivansto-wus2.mysql.database.azure.com:3306/flask_notes
   ```
5. Restart gunicorn: `systemctl restart flask-app`
6. Front Door will automatically stop sending traffic to Canada East once health probes fail

---

## Project Series

| Project | Description |
|---|---|
| a01 | Flask + SQLite, local |
| a02 | Flask + MySQL, local |
| a03 | Terraform: 2 Azure VMs (MySQL + App), West Europe |
| a04 | Terraform: App Gateway + Web VMSS + Internal NLB + App VMSS + MySQL VM |
| a05 | Terraform: Same as a04 with MySQL Flexible Server, Canada East |
| **a06** | **Terraform: Two-region active-active, Front Door, MySQL replication** |
