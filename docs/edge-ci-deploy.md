# Deploying the edge from CI

`.github/workflows/edge-deploy.yml` runs `01-cloud-edge/scripts/deploy.sh` from
a GitHub runner that has joined the tailnet as `tag:ci`. It carries no SSH key
and no master age key.

- **SSH needs no key.** The edge runs `tailscaled --ssh`, and
  `tailscale/policy.hujson` accepts `tag:ci → tag:cloud-edge` as root. The rule
  is `accept`, never `check`: a check wants a human at a browser and would hang
  the runner until the job times out.
- **The runner is confined to port 22 on the edge.** One grant, and a `tests`
  case asserting everything else is denied — the API evaluates those at
  `terraform plan`, so widening the grant fails the PR.
- **The node is ephemeral** and reaped when the job ends.

## The auth key, under tailnet lock

A locked tailnet will not admit a node whose key is unsigned, and an ephemeral
node has no key to sign until it exists. The way out is a **pre-signed** auth
key: sign it once, and every node that uses it is trusted.

OAuth clients cannot be used for this — signing applies to auth keys.

1. In the admin console, create an auth key that is **reusable**, **ephemeral**,
   **pre-approved**, and tagged `tag:ci`.
2. On a node holding a trusted tailnet-lock key:

   ```bash
   tailscale lock sign tskey-auth-xxxxCTRL-xxxxxxxxxx
   ```

   It prints the signed key.
3. Put that value in `sops/terraform.sops.yaml` as `tailscale_ci_authkey`:

   ```bash
   mise exec -- sops sops/terraform.sops.yaml
   ```

The workflow passes `--statedir=/tmp/tailscale-state` to `tailscaled`, which is
where the client keeps the key-authority data it verifies the signature against.

Re-signing is only needed when the key itself is replaced. Watch the number of
signing keys if you automate rotation — tailscale/tailscale#16607 covers keys
accumulating when each deploy signs a fresh authkey.

## What else the job needs

`SOPS_AGE_KEY` in the `edge` environment — the same terraform-only key the other
two workflows use. Everything else the runner needs is inside
`sops/terraform.sops.yaml`: the signed auth key, and `edge_json`, which the job
writes to `01-cloud-edge/edge.json` before deploying.

## The master age key is still on the box

`deploy.sh` pushes `secrets/age.key` to `/var/lib/sops-nix/key.txt` only when it
finds one locally, so CI skips that step and the box keeps the key it was
installed with. That key decrypts every `apps/base/**/*.sops.yaml`, and it lives
on a public-internet-facing VM.

The fix is to give sops-nix the box's own SSH host key as its identity, so the
master key can be deleted from the VM. An edge compromise then costs the four
values in that file instead of every secret in the repo.

**Half done.** `01-cloud-edge/.sops.yaml` now carries the host key's age
recipient (`age1v5jydk3…`, derived from `/etc/ssh/ssh_host_ed25519_key.pub` with
`ssh-to-age`) alongside the key you edit with, and `install.sh` seeds that host
key so a reinstall keeps the recipient valid. What remains, in order:

1. Re-encrypt to both recipients:

   ```bash
   cd 01-cloud-edge && sops updatekeys nixos/hosts/oracle-edge/secrets.sops.yaml
   ```

2. In `nixos/hosts/oracle-edge/secrets.nix`, add the host key **while keeping**
   `keyFile` — sops-nix tries every identity, so the old one still carries the
   deploy if the new path is wrong:

   ```nix
   age = {
     keyFile     = "/var/lib/sops-nix/key.txt";
     sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
     generateKey = false;
   };
   ```

3. Deploy. On the box: `systemctl status sops-nix` active, `/run/secrets/`
   populated. **Reboot and check again** — activation-time and boot-time
   identity resolution are separate paths.
4. Drop `keyFile`, deploy, verify `/run/secrets/` again. This run proves the
   host key is doing the work.
5. On the box: `rm -f /var/lib/sops-nix/key.txt`. This is the step that removes
   the master key from the VM.
6. Save the box's `/etc/ssh/ssh_host_ed25519_key{,.pub}` to 1Password as
   `secrets/edge-host-ed25519{,.pub}`; `install.sh` needs them to reinstall.
   Then delete the age-key block from `install.sh` and
   `01-cloud-edge/scripts/push-age-key.sh` with its mise task.

If sops-nix cannot decrypt, activation fails and takes tailscaled's authkey and
ACME's `CF_DNS_API_TOKEN` with it. The box stays up on existing state, so this
is a failed deploy rather than a lost box; recovery is
`scp secrets/age.key root@<edge>:/var/lib/sops-nix/key.txt` and restoring
`keyFile`.
