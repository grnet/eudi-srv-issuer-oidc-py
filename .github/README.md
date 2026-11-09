# EUDIW Issuer Authorization Server (GRNET fork)

See [README.md](README.md) for the original README.

## Setup

1. Install Python virtual environment and dependencies:

```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Edit file `config.yaml` and set hostname/IP for the server. (Before
   upstream 0.10.0 this was `config.json`.) The Docker image ships no
   configuration: mount one at `/etc/issuer_config/authorization_config.yaml`.

## Use

```
source .venv/bin/activate
./run.sh
```

