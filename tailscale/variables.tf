# Every value here is a credential for reading the proxmox root's state.

# ---------------------------------------------------------------- backend ----
#
# The proxmox root's state is read through a terraform_remote_state data source,
# and a data source takes no -backend-config: its credentials have to be real
# values. They arrive as TF_VAR_* from secrets/oci.env (scripts/oci-env.sh), and
# in CI from the repository secrets, so none of them reach a tfvars file.

variable "oci_namespace" {
  description = "Object Storage namespace holding the state bucket"
  type        = string
}

variable "oci_region" {
  description = "Region the state bucket lives in"
  type        = string
}

variable "oci_tenancy_ocid" {
  description = "Tenancy OCID"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCID of the user whose API key signs the state read"
  type        = string
}

variable "oci_fingerprint" {
  description = "Fingerprint of that user's API signing key"
  type        = string
}

variable "oci_private_key_path" {
  description = "Path to the API signing key; defaults to secrets/oci_api_key.pem"
  type        = string
}
