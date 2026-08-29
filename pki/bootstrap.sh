#!/usr/bin/env bash
#
# Mint the development CA shared by both stacks, and publish it into a Docker
# named volume the two compose projects mount.
#
# Why a volume rather than a directory: the issuer and the authorization server
# live in separate repositories that must both trust the same root. A relative
# path like ../eudi-srv-issuer-oidc-py assumes a particular checkout layout and
# breaks the moment someone clones elsewhere. A named volume is addressed by
# name, so neither repo needs to know where the other one sits on disk.
#
# This is the OIDC repo's script because the OIDC stack starts first (the issuer
# joins its network). Run it once; both stacks pick the material up from there.
#
# TLS only. The mdoc document-signing chain (IACA + PID-DS) is a separate PKI
# and is handled in the issuer repo by pki/bootstrap.sh.
#
# Everything produced here is throwaway test material. Nothing is a real key.

set -euo pipefail

cd "$(dirname "$0")"
OUT="out"
VOLUME="${PKI_VOLUME:-eudiw-pki}"
DAYS_CA=3650
DAYS_LEAF=825   # ~27 months; anything longer is rejected by modern clients

# One leaf per service in the stack. The names must match the compose service
# names / network aliases, because that is the hostname one container uses to
# dial another. localhost and
# 127.0.0.1 are included so the same certificate works from the host, the
# browser, curl, and the wallet all arrive that way.
SERVICES=(issuer oidc frontend)

mkdir -p "$OUT"

# ── Root CA ─────────────────────────────────────────────────────────────────
if [[ -f "$OUT/ca.key" && -f "$OUT/ca.crt" ]]; then
  echo "==> Reusing existing dev CA ($OUT/ca.crt)"
else
  echo "==> Creating dev root CA"
  openssl req -x509 -newkey rsa:4096 -sha256 -days "$DAYS_CA" -nodes \
    -keyout "$OUT/ca.key" -out "$OUT/ca.crt" \
    -subj "/C=GR/O=GRNET/OU=EUDIW local dev/CN=EUDIW Local Dev CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
fi

# REQUESTS_CA_BUNDLE / SSL_CERT_FILE want a PEM bundle. With a single root that
# is just the root, but the distinct name keeps the intent readable at the
# mount points.
cp "$OUT/ca.crt" "$OUT/ca-bundle.pem"

# ── Per-service leaf certificates ───────────────────────────────────────────
for svc in "${SERVICES[@]}"; do
  if [[ -f "$OUT/$svc.crt" && -f "$OUT/$svc.key" ]]; then
    echo "==> Reusing existing certificate for '$svc'"
    continue
  fi

  echo "==> Issuing certificate for '$svc'"

  # SANs, not CN: modern TLS stacks ignore CN entirely. Both names matter,
  # the service name for container-to-container calls, localhost for the host.
  cat > "$OUT/$svc.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$svc,DNS:localhost,IP:127.0.0.1
EOF

  openssl req -newkey rsa:2048 -nodes \
    -keyout "$OUT/$svc.key" -out "$OUT/$svc.csr" \
    -subj "/C=GR/O=GRNET/OU=EUDIW local dev/CN=$svc" 2>/dev/null

  openssl x509 -req -in "$OUT/$svc.csr" \
    -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" -CAcreateserial \
    -out "$OUT/$svc.crt" -days "$DAYS_LEAF" -sha256 \
    -extfile "$OUT/$svc.ext" 2>/dev/null

  rm -f "$OUT/$svc.csr" "$OUT/$svc.ext"
done

# Readable by whatever uid the containers run as. These are disposable dev keys;
# the alternative is chown games against a uid that differs per platform.
chmod 644 "$OUT"/*.key

# ── Publish into the shared volume ──────────────────────────────────────────
# Both compose projects mount this volume read-only. Recreating it on every run
# keeps it in step with out/ and makes the script safe to re-run.
echo "==> Publishing to Docker volume '$VOLUME'"
docker volume create "$VOLUME" >/dev/null
docker run --rm \
  -v "$VOLUME:/dest" \
  -v "$PWD/$OUT:/src:ro" \
  alpine:3.20 \
  sh -c 'rm -rf /dest/* && cp /src/*.crt /src/*.key /src/*.pem /dest/ && chmod 644 /dest/*' \
  >/dev/null

echo
echo "Done. CA and certificates are in pki/$OUT/ and volume '$VOLUME'."
echo
echo "To make your browser trust these certificates, import pki/$OUT/ca.crt:"
echo "  macOS  sudo security add-trusted-cert -d -r trustRoot \\"
echo "           -k /Library/Keychains/System.keychain pki/$OUT/ca.crt"
echo "  Linux  sudo cp pki/$OUT/ca.crt /usr/local/share/ca-certificates/eudiw-dev-ca.crt \\"
echo "           && sudo update-ca-certificates"
