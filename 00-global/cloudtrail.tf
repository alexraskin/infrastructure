module "cloudtrail" {
  source = "../modules/cloudtrail"

  name                = "account-trail"
  discord_webhook_url = module.secrets["global"].values["discord_webhook_url"]
}
