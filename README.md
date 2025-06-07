# infrastructure

This repo contains the infrastructure for my home lab. It is a 5 node swarm/glusterfs cluster, running on an Intel NUC, using Proxmox.

- main branch is the cluster
- pve2 branch is a single node
- vps branch is running on a VPS

## Architecture

![Architecture](https://i.gyazo.com/3922ff9ed576e1637beb43e5c612fcfe.png)


## swarmctl

Inside the cluster, is a service called `swarmctl` that is used to deploy the other services from their respective repos.

Check it out [here](https://github.com/alexraskin/swarmctl).

