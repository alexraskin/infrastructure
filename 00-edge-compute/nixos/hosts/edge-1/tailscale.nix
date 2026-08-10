{ unstable, ... }:
let

  flags = [
    "--accept-dns=false"

    "--ssh"
  ];
in
{
  services.tailscale = {
    enable = true;

    package = unstable.tailscale;

    openFirewall = true;

    authKeyFile = "/var/lib/tailscale-authkey";

    useRoutingFeatures = "none";

    extraUpFlags = flags;
    extraSetFlags = flags;
  };

}
