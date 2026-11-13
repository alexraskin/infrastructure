variable "name" {
  description = "Role name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the token.actions.githubusercontent.com provider in this account"
  type        = string
}

variable "repository" {
  description = "owner/repo the workflow runs in"
  type        = string
}

variable "environment" {
  description = "GitHub environment the job declares — the only subject the role trusts"
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket holding the Terraform state"
  type        = string
}

variable "state_key" {
  description = "State object the role reads, writes and locks; null for a job that runs no Terraform"
  type        = string
  default     = null
}

variable "read_state_keys" {
  description = "Other roots' state objects, read through terraform_remote_state"
  type        = list(string)
  default     = []
}

variable "ssm_parameter_arns" {
  description = "SSM parameters (and paths, for GetParametersByPath) the role reads"
  type        = list(string)
  default     = []
}
