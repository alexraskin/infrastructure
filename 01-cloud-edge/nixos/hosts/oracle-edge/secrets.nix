{ config, ... }:
{
  sops = {
    defaultSopsFile = ./secrets.sops.yaml;

    age = {
      # keyFile = "/var/lib/sops-nix/key.txt";
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
    gnupg.sshKeyPaths = [ ];

    secrets = {
      tailscale_authkey = { };
      cloudflare_dns_api_token = { };
    };

    templates."cloudflare-credentials".content = ''
      CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_dns_api_token}
    '';
  };
}
