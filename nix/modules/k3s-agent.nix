{
  config,
  cluster,
  node,
  name,
  ...
}:
{
  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = "/var/lib/k3s-token";

    # Agents talk to the kube-vip VIP, so losing one control-plane node is a no-op.
    serverAddr = "https://${cluster.vip}:6443";

    extraFlags = [
      "--node-name=${name}"
      "--node-ip=${node.ip}"
      # No node-role.kubernetes.io/* label here — kubelet rejects self-assigned
      # labels in that namespace and refuses to start entirely. Roles have to be
      # set from the API side: kubectl label node <n> node-role.kubernetes.io/worker=
    ];
  };

  networking.firewall.allowedTCPPorts = [ 10250 ]; # kubelet metrics
  networking.firewall.allowedUDPPorts = [ 8472 ]; # flannel vxlan

  environment.systemPackages = [ config.services.k3s.package ];
}
