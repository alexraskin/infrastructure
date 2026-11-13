terraform {
  required_version = ">= 1.12"

  backend "s3" {
    bucket       = "alexraskin-tfstate"
    key          = "infrastructure/oracle/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 6"
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

data "aws_ssm_parameter" "backup_user_email" {
  name = "/infrastructure/oracle/backup_user_email"
}

provider "oci" {
  tenancy_ocid = local.oci["tenancy_ocid"]
  user_ocid    = local.oci["user_ocid"]
  fingerprint  = local.oci["fingerprint"]
  private_key  = local.oci["private_key"]
  region       = local.oci["region"]
}
