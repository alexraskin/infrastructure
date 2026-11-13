data "aws_ssoadmin_instances" "this" {
  provider = aws.sso
}

data "aws_caller_identity" "current" {}

locals {
  sso_instance_arn  = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
}

resource "aws_identitystore_user" "alex" {
  provider          = aws.sso
  identity_store_id = local.identity_store_id

  user_name    = "alex"
  display_name = "Alex Raskin"

  name {
    given_name  = "Alex"
    family_name = "Raskin"
  }

  emails {
    value   = module.secrets["global"].values["sso_email"]
    type    = "work"
    primary = true
  }
}

resource "aws_identitystore_group" "admin" {
  provider          = aws.sso
  identity_store_id = local.identity_store_id
  display_name      = "Admin"
  description       = "Admin"
}

resource "aws_identitystore_group_membership" "alex_admin" {
  provider          = aws.sso
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.admin.group_id
  member_id         = aws_identitystore_user.alex.user_id
}

resource "aws_ssoadmin_permission_set" "admin" {
  provider         = aws.sso
  instance_arn     = local.sso_instance_arn
  name             = "AdministratorAccess"
  session_duration = "PT1H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  provider           = aws.sso
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_account_assignment" "alex_admin" {
  provider           = aws.sso
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  principal_type     = "USER"
  principal_id       = aws_identitystore_user.alex.user_id
  target_type        = "AWS_ACCOUNT"
  target_id          = data.aws_caller_identity.current.account_id
}
