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
    ./secrets.nix
    ./tailscale.nix
    ./acme.nix
    ./haproxy.nix
    ./logging.nix
    ./metrics.nix
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
      allowedTCPPorts = [ 443 ];
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

  # Reached over tailscale0 only; eth0 never opens 22.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.mutableUsers = false;

  nix = {
    settings = {
      allowed-users = [ "root" ];
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
