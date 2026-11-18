config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# The edge box runs NixOS via nixos-anywhere, so there is no Oracle Cloud Agent
# to run the monitoring plugin.
rule "oci_compute_instance_monitoring" {
  enabled = false
}

# The CNPG bucket sets versioning = "Disabled" deliberately; CNPG's own
# retentionPolicy owns backup expiry. See terraform/oracle/objectstorage.tf.
rule "oci_object_storage_bucket_versioning" {
  enabled = false
}

plugin "oci" {
  enabled = true
  version = "0.1.1"
  source  = "github.com/joelp172/tflint-ruleset-oci"

  signing_key = <<-KEY
  -----BEGIN PGP PUBLIC KEY BLOCK-----
  mDMEZ9lWDBYJKwYBBAHaRw8BAQdAzEHbV23E2TSQCqRU66OTevnXypPyk1cIdq2I
  Rx6ki8e0KEpvZWwgUGluZGVyIDxqb2VsLnBpbmRlckBwcm90b25tYWlsLmNvbT6I
  kwQTFgoAOxYhBJNOC76sc5HN/kHD+L3SQmX0bRPgBQJn2VYMAhsDBQsJCAcCAiIC
  BhUKCQgLAgQWAgMBAh4HAheAAAoJEL3SQmX0bRPgTFsBAO8hGsLsrK4rLDlCnUwt
  XfimtveFJQWSMUGZhbhp6mdLAP9I7suPIjgqZ11SMOYgLqbnJh4v1ljyUXMOkq7B
  hWDIArg4BGfZVgwSCisGAQQBl1UBBQEBB0BkwQ92oLAIXM//1zF+/vaRKPC6ZZBI
  7o7WAIcqN1iyLwMBCAeIeAQYFgoAIBYhBJNOC76sc5HN/kHD+L3SQmX0bRPgBQJn
  2VYMAhsMAAoJEL3SQmX0bRPg0eoBANoOcO6cggFrsR/dmBHvKl87R9FeMoUybn95
  9U3mQXOmAQCRsREiV4yzLsR2oCTQJyJ5d/hRsya5mKB77yJt3bk8AA==
  =PqA9
  -----END PGP PUBLIC KEY BLOCK-----
  KEY
}
