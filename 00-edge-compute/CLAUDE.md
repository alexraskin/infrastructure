# 00-edge-compute/ — the public edge

A free Oracle Cloud ARM box running HAProxy, terminating TLS on a public IP and
forwarding to home over Tailscale. It exists because **Plex cannot go through
the cloudflared tunnel**: Cloudflare's terms 2.8 restrict serving video through
the proxy, disabling caching does not change that (2.8 is about bytes crossing
their network), and a tunnel is proxied by definition — `*.cfargotunnel.com`
only resolves orange-clouded. Oracle rather than AWS purely for egress: 10 TB/mo
free against AWS's 100 GB, and a 4K remux direct-play is ~27 GB/hour.

Its own mise config (`mise trust` once) and its own Terraform root, state in R2
under `edge-compute/terraform.tfstate`. Structure follows
[FinnPL/Homelab-Setup `cloud-edge`](https://github.com/FinnPL/Homelab-Setup/tree/main/cloud-edge).

- **`edge.json` is the single source of truth**, like `hosts.json`: shape, zone,
  sites and their backends, read by `flake.nix` (`builtins.fromJSON`) and
  `terraform/network.tf` (`jsondecode`). One entry grows a DNS record, an ACME
  cert and an HAProxy backend. It is **gitignored** — the public hostnames are
  the one part of this setup worth not publishing, the same reasoning as
  `grafana-tailnet.sops.yaml`. Structure is in `edge.json.example`; a missing
  `edge.json` fails the flake eval and every `tf:*` task.
- **The flake root is `00-edge-compute/`, not a subdirectory.** A flake's source
  is copied into the store, so a flake in `nixos/` reading `../edge.json`
  resolves it to `/nix/store/edge.json` and fails with "access to absolute path
  … is forbidden in pure evaluation mode". `terraform/` reads `../edge.json`
  instead, which is why that path looks backwards.
- **Own flake, deliberately not another `hosts.json` entry.** The cluster flake
  is x86_64 and every node in it is a k3s node from one golden image; this is one
  aarch64 box in someone else's datacentre. Sharing it would make the cluster's
  `nix eval` checks depend on an Oracle instance. Cost is a duplicated ~30-line
  tailscale module.
- **Three phases**: `tf:apply` (Ubuntu ARM instance, public IP, DNS records) →
  `install` (nixos-anywhere: kexec, disko, install, reboot — one shot, erases
  the box, refuses if already NixOS) → `deploy` (push flake, switch, repeatable).
- **Both build on the box.** The build host is x86_64 and the instance is
  aarch64, so `scripts/deploy-node.sh`'s build-locally-then-`nix copy` cannot
  work. `--build-on-remote` hands it to the instance's Ampere cores; the kexec
  image is *substituted* prebuilt, a download rather than a build, so no
  emulation is involved. `deploy` ships the tree with tar over ssh, not rsync —
  rsync must exist on both ends and is not in a minimal NixOS profile, so the
  first deploy would be the one that fails.
- **The public IP is ephemeral on purpose.** A reserved OCI IP cannot be
  attached at create time, only afterwards and only to an instance that has no
  ephemeral one — which means no internet during first boot and no unattended
  install. Taking the ephemeral address and having `terraform/dns.tf` point the
  A records at `oci_core_instance.edge.public_ip` removes that ordering problem.
  This is also why the Cloudflare provider is in *this* root and not
  `terraform/cloudflare/`: the value only exists here.
- **`proxied = false` on those records is load-bearing.** Orange-clouding puts
  the video back on Cloudflare's network and back under 2.8.
- **"Out of host capacity" is the normal failure**, not a misconfiguration.
  Always-free A1 capacity is scarce and uneven across availability domains;
  `mise run tf:apply` walks every AD, retrying on that error only.
- **TLS terminates at the edge**, unlike the reference design's SNI passthrough.
  There is no reverse proxy at home to hand the connection to, and Plex serves
  its own `*.plex.direct` cert, which is not valid for the name clients dial.
  Certs are LetsEncrypt over **DNS-01**, which is why port 80 is closed in both
  the OCI security list and the NixOS firewall.
- **Tailscale here is a leaf with no `--accept-routes`.** The Plex host is its
  own tailnet device, so the backend is a peer address; accepting the cluster's
  `10.0.200.0/24` would give the one machine with a public IP a path to the whole
  LAN, and would hairpin every stream through whichever k3s server owns the
  route. Its pre-auth key is `secrets/tailscale-authkey-edge` — tagged, so the
  ACL can grant it exactly the one `host:port` in `edge.json` and nothing else.
- **`--ssh` is on, as break-glass.** tailscaled serves port 22 on the tailnet
  address, so a dead sshd no longer means a trip to the OCI serial console —
  which is what it meant once, with 22 removed from the security list and no
  other way in. sshd still owns the public IP, which is what `scripts/deploy.sh`
  and every `mise` task here connect to (`terraform output -raw public_ip`), so
  automation is untouched. The matching rule in `tailscale/policy.hujson` is
  `autogroup:admin` → `tag:edge`, users `root`, **`accept` not `check`**: check
  puts a browser re-auth in front of every connection, fine for a human and
  fatal for anything unattended. It cannot ride on the existing rule, whose
  `dst` is `autogroup:self` — that means devices owned by the calling user, and
  a tagged node has no owner.
- **`logging.nix` ships the journal to the cluster's Loki**, over the tailnet,
  to the operator-served LoadBalancer in `apps/base/loki/service.yaml`, at the
  bare MagicDNS name `http://loki:3100/loki/api/v1/push`. It is
  `services.alloy`, matching what the cluster runs, not promtail.
  - HAProxy logs with `log /dev/log local0 info` and journald owns `/dev/log`,
    so haproxy, tailscaled, `acme-*.service`, sshd and the kernel are one
    journal and one `loki.source.journal` collects all of them. No rsyslog.
  - `services.journald.storage = "persistent"` — the default is volatile when
    `/var/log/journal` is absent, which drops anything not yet shipped across a
    reboot.
  - The job label is `edge-journal`, deliberately **not** `systemd-journal`:
    that is what the in-cluster DaemonSet labels the six k3s nodes with, and
    reusing it folds an Oracle box into every existing
    `{job="systemd-journal"}` query without anyone noticing.
  - Alloy's UI listens on `0.0.0.0:12345` by default, and `default.nix` sets
    `trustedInterfaces = [ "tailscale0" ]` — which opens *every* port to every
    tailnet peer regardless of `allowedTCPPorts`. `extraFlags` binds it to
    loopback instead.
  - **`--accept-dns=true` in `tailscale.nix` is a dependency of this**, not a
    preference. It is what installs `search <tailnet>.ts.net` in `resolv.conf`,
    which is the whole reason the bare name `loki` resolves — the same mechanism
    behind `ssh <node>` on any MagicDNS client. `*.ts.net` is *not* published in
    public DNS, so with `accept-dns` false the box has no resolver for the name
    at all and `loki.write` logs `dial tcp: lookup … no such host` on a retry
    loop forever while Alloy otherwise looks perfectly healthy: unit active,
    config valid, journal source running.
  - The URL is a literal here rather than a field in the gitignored `edge.json`,
    which is only true because it is a bare name. An HTTPS Ingress would force
    the FQDN into it and the tailnet name would have to be hidden again.
- **The first ACME run always fails, and nothing retries it.** nixos-anywhere
  activates the whole config during `install`, before `push-secrets.sh` has put
  `/etc/cloudflare/credentials` on the box, so the acme unit dies with "Failed
  to load environment files". A later `deploy` does *not* fix it: the unit's
  definition has not changed, so `switch-to-configuration` leaves the failed
  oneshot alone, and HAProxy goes on serving the self-signed placeholder that
  acme writes so services can start. The site answers on 443 and fails
  verification — `curl -w '%{ssl_verify_result}'` returns 19, not 0. `deploy.sh`
  now starts `acme-<domain>.service` explicitly after the switch, which is
  idempotent (the unit checks expiry before contacting LetsEncrypt).
- Credentials all come from `secrets/` via `scripts/tf-env.sh` as `TF_VAR_*`:
  `oci.env`, `oci_api_key.pem` (the signing key; `oci_api_key_public.pem` is
  already uploaded to OCI and unread here), and the existing
  `cloudflare-api-token`, which is also pushed to the box for ACME DNS-01.

## Gotchas

- **Enabling `--ssh` makes the policy file load-bearing for SSH.** tailscaled
  intercepts port 22 on the tailnet address unconditionally once the flag is
  set, and if no `ssh` rule matches it **refuses** the connection rather than
  falling through to sshd. So turning it on without the matching rule is
  strictly worse than leaving it off: it breaks tailnet SSH that used to work.
- **`Connection refused` on a tailnet address does not mean "firewalled".**
  `00-edge-compute`'s `default.nix` sets `trustedInterfaces = [ "tailscale0" ]`,
  so every port is accepted on that interface regardless of `allowedTCPPorts`
  and the kernel RSTs anything with no listener. A closed port and a port whose
  daemon has died look identical, and both look nothing like a dropped packet —
  an OCI security-list removal times out instead. Probing a port nothing has
  ever served (`/dev/tcp/<ip>/9999`) tells you which of the two you are in:
  refused there means the interface is wide open and the daemon is simply gone.
