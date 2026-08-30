# Local development with Docker: authorization server

Runs the OIDC authorization server as a container over HTTPS, with certificate
verification switched **on**. No virtualenv, no `sudo`, no `certbot`.

This service pairs with the PID issuer, which lives in its own repository
(`eudi-srv-web-issuing-eudiw-py`) and has its own `DOCKER.md`. **Start this one
first**: it creates the Docker network and the development CA that both stacks
share. The issuer's stack joins them.

## Quick start

```sh
./pki/bootstrap.sh     # once; mints the CA both services trust
docker compose up --build
```

Then, from this directory:

```sh
curl --cacert pki/out/ca.crt https://localhost:5601/.well-known/openid-configuration
```

No `-k`. If that returns JSON, TLS is verifying properly.

The service listens on <https://localhost:5601>.

To stop a browser warning on that URL, import the root certificate:

```sh
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain pki/out/ca.crt

# Linux
sudo cp pki/out/ca.crt /usr/local/share/ca-certificates/eudiw-dev-ca.crt \
  && sudo update-ca-certificates
```

## What the CA script does

`pki/bootstrap.sh` mints one root certificate authority and a leaf
certificate per service, then copies everything into a Docker **named volume**
called `eudiw-pki`.

The issuer lives in a separate repository and must trust the same root. A
relative path like `../eudi-srv-issuer-oidc-py` would assume a
particular checkout layout. A named volume is addressed by name, so neither
repository needs to know where the other one sits on disk, and the two can be
cloned anywhere.

Each leaf carries two subject alternative names, the compose service name and
`localhost`, because the service is reached both ways:

| From | URL | Used for |
| --- | --- | --- |
| the issuer container | `https://oidc:5601` | `/introspection`, `/verify/user`, preauth |
| the wallet or browser | `https://localhost:5601` | the OAuth redirect flow |

One certificate covers both, so neither path needs verification disabled.

Everything under `pki/out/` is disposable test material and is gitignored.
Re-running the script reuses an existing CA; delete `pki/out/` to start over.

## What was changed to make this run in a container

Three things were hardcoded to the okeanos VM.

**`server.py`** read the bind address and TLS paths from literals, which meant
the server could only run on that one VM. All four values now come from the
config file, which already carried them:

| Was | Now reads |
| --- | --- |
| `"snf-74864.ok-kno.grnetcloud.net"` | `webserver.host`, falling back to `webserver.domain` |
| `web_conf["port"]` | unchanged |
| `"/etc/letsencrypt/live/snf-74864…/fullchain.pem"` | `webserver.server_cert` |
| `"/etc/letsencrypt/live/snf-74864…/privkey.pem"` | `webserver.server_key` |

`host` is the one key that did not already exist. It is needed because
`domain` is what the server *advertises*: idpyoidc interpolates it into `issuer`
and every endpoint URL, so it carries a port when the service is not on 443,
which makes it unusable as a bind address. It is optional, so a config without it
binds `domain` exactly as before.

**`docker/config.json`** is the repo's own `config.json` with the deployment
hostname and the TLS paths changed, and nothing else:

| Key | `config.json` | `docker/config.json` |
| --- | --- | --- |
| `webserver.server_cert` / `server_key` | `certs/client.*` | `/etc/eudiw/tls/oidc.*` |
| `domain` | the okeanos hostname | `localhost:5601` |
| `base_url`, `authorization_redirect_url` | the okeanos hostname | `https://localhost:5601` / `:5600` |
| `op.…` (2 token endpoint URLs) | the okeanos hostname | `https://localhost:5601` |

`domain` carries the port because idpyoidc interpolates `{domain}` into `issuer`
and the endpoint URLs, and has no separate `{port}` placeholder.

**`docker/openid-configuration.json`** is the container's copy of the discovery
document. `views.py` serves that file straight off disk
(`send_from_directory` over the app root), so the nine absolute URLs inside it
are beyond the reach of any config setting. The container mounts this copy over
the repo's, which leaves the tracked file untouched. It differs only in the
hostname.

The `Dockerfile` also no longer runs `run.sh`, which activates a virtualenv that
does not exist inside an image where dependencies are installed system-wide.

## Two compose files in this repo

Upstream ships `docker-compose.yml`, which pulls the published `ghcr.io` image.
It is untouched and still works:

```sh
docker compose -f docker-compose.yml up
```

Compose prefers `compose.yaml`, so a bare `docker compose up` runs the local
development stack instead. With both files present Compose prints
`Found multiple config files with supported names` on every command, followed by
the one it chose. That warning is noise rather than a problem.

## Day to day

```sh
docker compose up -d              # start
docker compose logs -f            # follow logs
docker compose restart            # after editing docker/config.json (mounted)
docker compose up -d --build      # after changing requirements.txt
docker compose down               # stop
```

## Troubleshooting

**`Missing cert or key`**. The CA has not been minted yet. Run
`./pki/bootstrap.sh`.

**Issuer cannot reach this service**. Check both are on the shared network:
`docker network inspect eudiw-dev`. This stack must be up first.

**Certificate errors after regenerating the CA**. The leaves changed but running
containers still hold the old ones. `docker compose restart` in both repositories.
