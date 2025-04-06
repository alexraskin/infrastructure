# infrastructure

This repo contains the infrastructure for my home lab. It is a 5 node swarm/glusterfs cluster, running on an Intel NUC, using Proxmox.

## Architecture

![Architecture](https://i.gyazo.com/cd2ebab0d170fe6f2cbd27991c693b85.png)


## swarmctl

Inside the cluster, is a service called `swarmctl` that is used to deploy the other services from their respective repos.

Check it out [here](https://github.com/alexraskin/swarmctl).

