{
  config,
  lib,
  pkgs,
  cluster,
  node,
  name,
  bootstrapIp,
  ...
}:
let
  isBootstrap = name == cluster.bootstrap;

  kubeVip = pkgs.writeText "kube-vip.yaml" (
    builtins.replaceStrings
      [ "@vip@" "@interface@" "@version@" ]
      [ cluster.vip cluster.interface cluster.kube_vip_version ]
      (builtins.readFile ../kube-vip.yaml.in)
  );
in
{
  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = "/var/lib/k3s-token";

    # First server initialises the embedded-etcd cluster; the rest join it.
    clusterInit = isBootstrap;
    serverAddr = lib.mkIf (!isBootstrap) "https://${bootstrapIp}:6443";

    extraFlags = [
      # Pin the k3s node name instead of inheriting whatever the kernel hostname
      # happens to be at start-up — two nodes both still called "nixos" collide
      # with "etcd cluster join failed: duplicate node name found".
      "--node-name=${name}"
      "--node-ip=${node.ip}"
      "--tls-san=${cluster.vip}"
      "--tls-san=${cluster.name}.${cluster.domain}"
      "--disable=traefik"
      "--disable=servicelb"
      "--write-kubeconfig-mode=0640"
    ];
  };

  # kube-vip provides the floating control-plane VIP. services.k3s.manifests links
  # the file into /var/lib/rancher/k3s/server/manifests *before* k3s starts —
  # doing this with systemd-tmpfiles instead loses the race, because the manifests
  # directory does not exist yet when tmpfiles runs on a fresh node.
  services.k3s.manifests = lib.mkIf isBootstrap {
    kube-vip.source = kubeVip;
  };

  networking.firewall.allowedTCPPorts = [
    6443 # kube-apiserver
    2379 # etcd client
    2380 # etcd peer
    10250 # kubelet metrics
  ];
  networking.firewall.allowedUDPPorts = [ 8472 ]; # flannel vxlan

  environment.systemPackages = [ config.services.k3s.package ];
  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
}
