# infrastructure

This repo contains the infrastructure for my home lab
## Architecture

![Architecture](https://i.gyazo.com/cd2ebab0d170fe6f2cbd27991c693b85.png)

## Deploy

```
docker stack deploy --compose-file docker-compose.yml <stack-name>
```

Inside the cluster, lives a service called `swarmctl` that is used to deploy the other services.