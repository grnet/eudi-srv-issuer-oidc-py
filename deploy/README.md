# Deploying the authorization server

This repository builds and publishes an image. It has no compose file, no
deploy workflow and no secrets of its own, because the container runs in the
issuer's stack.

    build here      ghcr.io/grnet/eudi-srv-issuer-oidc-py
    deployed from   grnet/eudi-srv-web-issuing-eudiw-py, under deploy/

**Since upstream 0.10.0 (merged here November 2026) the issuer's deploy does
not work with images from this branch yet.** It still renders the configuration
from `/app/config.json` inside the image, which 0.10.0 removed, and still sets
`allowed_htu`, which 0.10.0 no longer reads. Deploy an image built before the
merge until the issuer's `deploy/` is reworked as described below. The image the
demo runs is `sha-fe92cbb`.

## Why one stack for two services

The dependency runs one way. The issuer calls this service for `/introspection`
and `/preauth_generate`, and sends the browser to it; this service never calls
the issuer. The configuration naming both, `config_issuer_backend.yaml`, lives
in the issuer's repository.

Deploying separately would mean a private network for the server-to-server hop
that one repository owns and the other declares external, which is the ordering
constraint the local development stack had and the reason it had to be started
in a particular order.

## What the image needs from the deploy

The image ships no configuration. Its `Dockerfile` copies only `*.py`,
`run.sh` and `templates/`, and the container runs

    python3 server.py /etc/issuer_config/authorization_config.yaml

so the deploy must mount a complete configuration there. `config.yaml` at the
root of this repository is upstream's example, with its keys documented in
`api_docs/configuration.md`. Before 0.10.0 the image carried `/app/config.json`,
and the issuer's `deploy/render-oidc-config.py` merged a small patch over it;
that file is gone.

What varies per deployment:

| Key | For GRNET's demo |
| --- | --- |
| `domain` | `demo.eudiw.grnet.gr/issuer/oidc`. `op.server_info.issuer` is `https://{domain}`; with a path, every route is served under it, so the proxy must not strip the prefix (it did before 0.10.0) |
| `base_url` | `https://demo.eudiw.grnet.gr/issuer/oidc`: where the browser is sent, and what the metadata publishes |
| `frontends` | every key of the issuer's `frontend.frontends_config`. Each frontend gets its own issuer, `<issuer>/<frontend id>`, and the issuer must publish that in the frontend's `authorization_servers` |
| `authorization_redirect_url` | the issuer's `/auth_choice`, which now receives a signed `session_token` |
| `backend_api_key` | shared with the issuer's `authorization_server.api_key`; `/preauth_generate` answers 503 while it is unset or `change-me`. A secret |
| `op.server_info.endpoint.token.kwargs` | wallet attestation trust: `wallet_providers_lote_url` and `lote_signer_ca_path` (the Commission's wallet providers list, from GRNET's idpy-oidc), or `trusted_attesters_path`; `status_validator_url` |
| `require_pushed_authorization_requests`, `require_dpop`, `require_wallet_attestation` | all `true` by default, as HAIP asks; switch one off only to test a wallet that lacks it |

No longer configured: `allowed_htu`. The DPoP `htu` and the wallet attestation
PoP `aud` are each frontend's own issuer endpoints.

The server also writes its keys to `private/` on first start, and logs to
`/tmp/oidc_log`. Keep `private/` on a volume: regenerating the keys invalidates
outstanding tokens and the `session_token` the issuer verifies.

## Two URLs, two schemes

The issuer reaches this service two ways:

    base_url      https://demo.eudiw.grnet.gr/issuer/oidc   browser, through the proxy
    internal_url  http://oidc:5000                           issuer to here, in-network

Plain http internally is not a shortcut. `server.py` has no TLS context, so this
service speaks http and nginx-proxy terminates TLS. With the issuer path no
longer stripped, the internal URL carries the path too
(`http://oidc:5000/issuer/oidc`).

## Building

`docker-build.yml` publishes on push to `grnet` and `feat/**`. The image is
upstream's `Dockerfile` unchanged: multi-stage on `python:3.13-slim`, as the
unprivileged user 10001, listening on 5000. idpy-oidc comes from GRNET's fork,
`grnet/idpy-oidc`, for the wallet providers list. `requirements.txt` pins a
commit of its `grnet` branch, not the branch: the build caches the pip layer
by the file's content, so an unchanged `@grnet` line keeps the idpy-oidc of an
earlier build. Move the pin to take a new idpy-oidc.

To deploy a specific build, pass its tag as `oidc_image_tag` to the issuer's
Deploy workflow, or as the second argument of its local `deploy.sh`.
