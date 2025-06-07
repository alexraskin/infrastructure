terraform {
  backend "s3" {}
}

resource "hcloud_server" "node" {
  name        = var.server_name
  image       = var.image
  server_type = var.server_type
  location    = var.location
  user_data = templatefile("${path.module}/cloudinit.tpl", {
    ssh_public_key     = data.hcloud_ssh_key.ssh_key.public_key
    username           = var.server_username
    tailscale_auth_key = var.tailscale_auth_key
  })
  ssh_keys     = [data.hcloud_ssh_key.ssh_key.id]
  firewall_ids = [hcloud_firewall.firewall.id]
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  labels = {
    "name"      = var.server_name
    "terraform" = "true"
    "location"  = var.location
  }
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [ssh_keys]
  }
}

data "hcloud_ssh_key" "ssh_key" {
  name = var.ssh_public_key_name
}

resource "hcloud_firewall" "firewall" {
  name = "${var.server_name}-firewall-${var.location}"
  rule {
    direction = "in"
    protocol  = "tcp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    port = "80"
  }
  rule {
    direction = "in"
    protocol  = "tcp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    port = "443"
  }
  rule {
    direction = "in"
    protocol  = "udp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    port = "41641"
  }
}

resource "hcloud_snapshot" "snapshot" {
  server_id   = hcloud_server.node.id
  description = "Snapshot of ${var.server_name}"
}

