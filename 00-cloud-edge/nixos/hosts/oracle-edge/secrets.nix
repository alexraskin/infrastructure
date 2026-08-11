{ config, ... }:
{
  sops = {
    defaultSopsFile = ./secrets.sops.yaml;

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      # The file is encrypted to one recipient. Left at its default, sops-nix
      # would also offer the host's SSH key and fail confusingly on reinstall.
      sshKeyPaths = [ ];
    };
    gnupg.sshKeyPaths = [ ];

    secrets = {
      tailscale_authkey = { };
      cloudflare_dns_api_token = { };
    };

    # lego reads the token from the environment, so acme needs KEY=value rather
    # than the bare secret. `CF_DNS_API_TOKEN` is lego's scoped-token variable.
    templates."cloudflare-credentials".content = ''
      CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_dns_api_token}
    '';
  };
}
