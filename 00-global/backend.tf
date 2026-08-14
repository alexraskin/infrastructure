# Its own file because this root creates the bucket it points at. A backend block
# is honoured by `apply`, not just `init`, so rebuilding this bucket from nothing
# means moving this file aside for the first apply and migrating the state in
# afterwards — a one-off, written up in docs/terraform-state-migration.md.
#
# Partial on purpose like every other root: namespace and the API key come from
# secrets/oci.env via scripts/tf-init.sh.
terraform {
  backend "oci" {
    bucket = "infrastructure-terraform-state"
    key    = "global/terraform.tfstate"
  }
}
