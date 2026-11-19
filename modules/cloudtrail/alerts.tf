locals {
  alerts = {
    activity = {
      pattern = {
        detail = { errorCode = [{ exists = false }] }
        "$or" = [
          { "detail-type" = ["AWS Console Sign In via CloudTrail"] },
          { "detail-type" = ["AWS API Call via CloudTrail"], detail = { userIdentity = { type = ["Root"] } } },
          { "detail-type" = ["AWS API Call via CloudTrail"], source = ["aws.iam"] },
          {
            "detail-type" = ["AWS API Call via CloudTrail"]
            source        = ["aws.cloudtrail"]
            detail        = { eventName = ["StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors"] }
          },
        ]
      }
      template = "**<event>** by `<who>` from `<ip>` in `<region>`"
    }
    denied = {
      pattern = {
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail        = { errorCode = [{ prefix = "AccessDenied" }] }
      }
      template = "**<event>** `<err>` for `<who>` from `<ip>` in `<region>`"
    }
  }
}

resource "aws_cloudwatch_event_rule" "alerts" {
  for_each = local.alerts
  name     = "${var.name}-${each.key}"

  event_pattern = jsonencode(each.value.pattern)
}

resource "aws_cloudwatch_event_connection" "discord" {
  name               = "${var.name}-discord"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "x-unused"
      value = "unused"
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "discord" {
  name                             = "${var.name}-discord"
  connection_arn                   = aws_cloudwatch_event_connection.discord.arn
  invocation_endpoint              = var.discord_webhook_url
  http_method                      = "POST"
  invocation_rate_limit_per_second = 1
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "events_invoke" {
  statement {
    actions   = ["events:InvokeApiDestination"]
    resources = ["${aws_cloudwatch_event_api_destination.discord.arn}*"]
  }
}

resource "aws_iam_role" "alerts" {
  name               = "${var.name}-alerts"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

resource "aws_iam_role_policy" "alerts" {
  name   = "invoke-discord"
  role   = aws_iam_role.alerts.id
  policy = data.aws_iam_policy_document.events_invoke.json
}

resource "aws_cloudwatch_event_target" "discord" {
  for_each = aws_cloudwatch_event_rule.alerts
  rule     = each.value.name
  arn      = aws_cloudwatch_event_api_destination.discord.arn
  role_arn = aws_iam_role.alerts.arn

  input_transformer {
    input_paths = merge(
      {
        event  = "$.detail.eventName"
        who    = "$.detail.userIdentity.arn"
        ip     = "$.detail.sourceIPAddress"
        region = "$.region"
      },
      each.key == "denied" ? { err = "$.detail.errorCode" } : {},
    )
    input_template = "{\"content\": \"${local.alerts[each.key].template}\"}"
  }
}
