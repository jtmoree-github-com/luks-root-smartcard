#!/bin/sh

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [pkcs11-url]" >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  URL="$1"
  if ! printf '%s\n' "$URL" | grep -q '^pkcs11:'; then
    echo "Provided URL must start with pkcs11:" >&2
    exit 2
  fi
fi

if [ ! -d ~/.eid ] ; then
  mkdir -p ~/.eid
  chmod 0755 ~/.eid
fi

if [ -z "${URL:-}" ]; then
  URL=$(p11tool --list-all-privkeys --only-urls 2>/dev/null | \
    grep -Eiv 'sig|signature' | \
    grep -Ei 'auth|enc|decrypt' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  URL=$(p11tool --list-all-privkeys --only-urls 2>/dev/null | \
    grep -Ei 'sig|signature' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  URL=$(p11tool --list-all-privkeys --only-urls 2>/dev/null | head -n 1)
fi

if [ -z "${URL:-}" ]; then
  echo "Unable to find an encryption/authentication PKCS#11 key URL." >&2
  exit 1
fi

req_pem=$(mktemp "${TMPDIR:-/tmp}/p11cert-req.XXXXXX.pem")
trap 'rm -f "$req_pem"' EXIT

openssl req -engine pkcs11 -new -x509 -key "$URL" -keyform engine -out "$req_pem" -subj "/CN=$USER"
cat "$req_pem" >> ~/.eid/authorized_certificates
chmod 0644 ~/.eid/authorized_certificates