module "secrets" {
  source   = "../modules/ssm-params"
  for_each = local.secrets

  group      = each.key
  parameters = each.value
}

locals {
  secrets = {
    global = {
      budget_email = "Where the account budget alerts go"
      sso_email    = "Email on the Identity Center user"
    }
    oci = {
      tenancy_ocid     = "OCI tenancy, for the oracle and edge roots"
      user_ocid        = "OCI API user"
      fingerprint      = "Fingerprint of the OCI API key"
      private_key      = "OCI API private key (PEM) — can create and destroy"
      region           = "OCI region"
      compartment_ocid = "Compartment the oracle and edge roots build in"
    }
    oracle = {
      backup_user_email = "Primary email Identity Domains demands on the CNPG backup user"
    }
    proxmox = {
      pve_api_token = "Proxmox API token, terraform@pve!tf=..."
    }
    cloudflare = {
      api_token = "Zone/DNS/Edit + Zone/Zone/Read, for the cloudflare and edge roots"
    }
    tailscale = {
      oauth_client_id     = "Tailscale OAuth client, local runs only (CI federates over OIDC)"
      oauth_client_secret = "Tailscale OAuth client secret"
    }
    edge = {
      ssh_public_key       = "Authorized key on the edge box"
      tailscale_ci_authkey = "Ephemeral, reusable, tailnet-lock-signed key the edge deploy joins with"
      edge_json            = "01-cloud-edge/edge.json, verbatim"
    }
  }
}

