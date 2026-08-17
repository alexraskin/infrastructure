locals {
  waf_hosts = sort(distinct(concat(local.tunnel_hostnames, var.waf_extra_hosts)))

  waf_host_set = "http.host in {${join(" ", [for h in local.waf_hosts : jsonencode(h)])}}"

  waf_path_probes = join(" or ", [
    for path in var.waf_blocked_paths :
    "lower(http.request.uri.path) contains ${jsonencode(path)}"
  ])

  waf_scraper_agents = join(" or ", [
    for agent in var.waf_blocked_user_agents :
    "lower(http.user_agent) contains ${jsonencode(agent)}"
  ])

  waf_write_methods = "(${local.waf_host_set}) and http.request.method in {\"POST\" \"PUT\" \"PATCH\" \"DELETE\" \"TRACE\" \"CONNECT\"}"

  waf_junk_expression = join(" or ", compact([
    length(var.waf_blocked_paths) > 0 ? "(${local.waf_path_probes})" : "",
    length(var.waf_blocked_user_agents) > 0 ? "(${local.waf_scraper_agents})" : "",
  ]))

  waf_adopted_rules = [
    {
      ref               = "verified_bots"
      description       = "Defense"
      action            = "managed_challenge"
      expression        = "(cf.client.bot)"
      action_parameters = null
    },
  ]

  waf_custom_rules = concat(local.waf_adopted_rules, [
    {
      ref               = "block_junk"
      description       = "Probe paths, and scrapers that ignore robots.txt"
      action            = "block"
      expression        = local.waf_junk_expression
      action_parameters = null
    },
    {
      ref               = "read_only_hosts"
      description       = "The tunnel serves static sites — nothing behind it takes a write"
      action            = "block"
      expression        = local.waf_write_methods
      action_parameters = null
    },
    {
      ref               = "no_user_agent"
      description       = "Challenge requests with no User-Agent that are not a verified crawler"
      action            = "managed_challenge"
      expression        = "(http.user_agent eq \"\") and not cf.client.bot"
      action_parameters = null
    },
  ])
}

check "waf_fits_the_free_plan" {
  assert {
    condition     = length(local.waf_custom_rules) <= 5
    error_message = "${length(local.waf_custom_rules)} custom rules — the Free plan takes 5. Fold two expressions together rather than dropping one."
  }
}

resource "cloudflare_ruleset" "waf_custom" {
  for_each = var.waf_enabled ? var.zones : {}

  zone_id     = each.value
  name        = "default"
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  description = "terraform: ${each.key}"

  rules = local.waf_custom_rules
}

resource "cloudflare_ruleset" "waf_ratelimit" {
  for_each = var.waf_enabled && var.waf_rate_limit.enabled ? var.zones : {}

  zone_id     = each.value
  name        = "default"
  kind        = "zone"
  phase       = "http_ratelimit"
  description = "terraform: ${each.key}"

  rules = [{
    ref         = "per_ip_flood"
    description = "Per-IP flood control"
    action      = var.waf_rate_limit.action
    # The Free plan allows only Path and Verified Bot here, so this is zone-wide.
    expression = "not cf.client.bot"

    ratelimit = {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 10
      mitigation_timeout  = 10
      requests_per_period = var.waf_rate_limit.requests_per_period
    }
  }]
}
