{
  pkgs,
  edge,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./ssh-keys.nix
    ./tailscale.nix
    ./acme.nix
    ./haproxy.nix
    ./logging.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  system.activationScripts.liveHostname.text = ''
    echo "${edge.instance.hostname}" > /proc/sys/kernel/hostname
  '';

  networking = {
    hostName = edge.instance.hostname;
    useDHCP = false;
    useNetworkd = true;
    dhcpcd.enable = false;
    nftables.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        443
      ];
      allowedUDPPorts = [ 41641 ];
      trustedInterfaces = [ "tailscale0" ];

      checkReversePath = "loose";
    };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-uplink" = {
      matchConfig.Name = "eth0";
      networkConfig.DHCP = "yes";
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  services.fail2ban.enable = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  time.timeZone = "UTC";
  services.timesyncd.enable = true;
  documentation.enable = false;
  documentation.nixos.enable = false;
  system.stateVersion = "25.05";

  environment.systemPackages = with pkgs; [
    jq
    curl
    dnsutils
    tcpdump
    htop
    vim
  ];
}
