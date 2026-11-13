terraform {
  required_version = ">= 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 6"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

# Secrets come from SSM, put there by 00-global. Same SSO session as the backend.
provider "aws" {
  region = "us-east-1"
}

data "aws_ssm_parameters_by_path" "oci" {
  path            = "/infrastructure/oci"
  with_decryption = true
}

locals {
  oci = zipmap([for n in data.aws_ssm_parameters_by_path.oci.names : basename(n)], data.aws_ssm_parameters_by_path.oci.values)
}

data "aws_ssm_parameter" "cloudflare_api_token" {
  name = "/infrastructure/cloudflare/api_token"
}

data "aws_ssm_parameter" "ssh_public_key" {
  name = "/infrastructure/edge/ssh_public_key"
}

provider "oci" {
  tenancy_ocid = local.oci["tenancy_ocid"]
  user_ocid    = local.oci["user_ocid"]
  fingerprint  = local.oci["fingerprint"]
  private_key  = local.oci["private_key"]
  region       = local.oci["region"]
}

provider "cloudflare" {
  api_token = data.aws_ssm_parameter.cloudflare_api_token.value
}
