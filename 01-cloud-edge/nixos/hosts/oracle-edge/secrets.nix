{ config, ... }:
{
  sops = {
    defaultSopsFile = ./secrets.sops.yaml;

    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
    gnupg.sshKeyPaths = [ ];

    secrets = {
      tailscale_authkey = { };
      route53_access_key_id = { };
      route53_secret_access_key = { };
    };

    # Key of the acme-edge IAM user; it may only write its own _acme-challenge records.
    templates."route53-credentials".content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.route53_access_key_id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.route53_secret_access_key}
      AWS_REGION=us-east-1
      AWS_HOSTED_ZONE_ID=Z03255151MKN439N2SA2I
    '';
  };
}
