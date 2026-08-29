FROM python:3.11-slim

COPY . .

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip and install Python dependencies
RUN python -m pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# Expose the authorization server port
EXPOSE 5601

# Not run.sh: it activates a virtualenv that does not exist here, since the
# dependencies above are installed into the system interpreter. run.sh is
# unchanged and still what the VM uses.
#
# compose.yaml overrides this with the container config (docker/config.json,
# mounted at /config.json). The default below keeps the image runnable on its
# own, using the repo's config.
CMD ["python3", "server.py", "config.json"]
