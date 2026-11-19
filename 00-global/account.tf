resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "account"
  type          = "ACCOUNT"
}

resource "aws_account_alternate_contact" "this" {
  for_each = toset(["SECURITY", "BILLING", "OPERATIONS"])

  alternate_contact_type = each.key
  name                   = aws_identitystore_user.alex.display_name
  title                  = "Owner"
  email_address          = module.secrets["global"].values["budget_email"]
  phone_number           = module.secrets["global"].values["contact_phone"]
}

resource "aws_ce_anomaly_monitor" "services" {
  name              = "services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "daily" {
  name             = "daily"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  subscriber {
    type    = "EMAIL"
    address = module.secrets["global"].values["budget_email"]
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["1"]
    }
  }
}
