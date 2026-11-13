data "aws_caller_identity" "this" {}

# Adopted from the old OCI global state; drop once applied.
import {
  to = aws_budgets_budget.monthly
  id = "${data.aws_caller_identity.this.account_id}:monthly-cost"
}

resource "aws_budgets_budget" "monthly" {
  name         = "monthly-cost"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = ["ACTUAL", "FORECASTED"]
    content {
      notification_type          = notification.value
      comparison_operator        = "GREATER_THAN"
      threshold                  = 100
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [data.sops_file.admin.data["budget_email"]]
    }
  }
}
