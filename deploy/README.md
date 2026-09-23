# Deploying the authorization server

This repository builds and publishes an image. It has no compose file, no
workflow and no secrets of its own, because the container runs in the issuer's
stack.

    build here      ghcr.io/grnet/eudi-srv-issuer-oidc-py
    deployed from   grnet/eudi-srv-web-issuing-eudiw-py, under deploy/

## Why one stack for two services

The dependency runs one way. The issuer calls this service for `/introspection`
and `/verify/user`; this service never calls the issuer. The configuration
naming both, `config_issuer_backend.yaml`, lives in the issuer's repository.

Deploying separately would mean a private network for the server-to-server hop
that one repository owns and the other declares external, which is the ordering
constraint the local development stack had and the reason it had to be started
in a particular order.

## What the deploy does with this repository

Pulls the image by tag, and mounts a configuration rendered from the one inside
it.

`config.json` here is used as shipped. Four values vary per deployment, so
`deploy/render-oidc-config.py` in the issuer's repository reads the config out of
the image and merges `deploy/oidc-config.patch.json` over it:

| Key | Why |
| --- | --- |
| `domain` | `idpyoidc` expands `{domain}`, so this also sets `server_name`, `op.server_info.issuer` and `webserver.domain` |
| `base_url` | what the browser is redirected to, and what appears in published metadata |
| `authorization_redirect_url` | the authentication-method page, served by the issuer, so it carries the issuer's prefix |
| `op.server_info.add_ons.dpop.kwargs.allowed_htu` | DPoP allowlist; a token request whose URL is not listed is rejected, so it must name the token endpoint as the wallet sees it |

Upstream's other 355 lines are used unchanged, and nothing deployment-specific
is committed here.

## Two URLs, two schemes

The issuer reaches this service two ways:

    base_url      https://demo.eudiw.grnet.gr/auth   browser, through the proxy
    internal_url  http://oidc:5000                    issuer to here, in-network

Plain http internally is not a shortcut. `server.py` has its `ssl_context`
commented out, so this service speaks http and nginx-proxy terminates TLS.

## Building

`docker-build.yml` publishes on push to `grnet` and `feat/**`. The image is
upstream's `Dockerfile` unchanged: multi-stage on `python:3.13-slim`, listening
on 5000, reading its config from
`/etc/issuer_config/authorization_config.json`.

To deploy a specific build, pass its tag as `oidc_image_tag` to the issuer's
Deploy workflow, or as the second argument to its `deploy.sh`.
