#!/bin/bash
set -e

CERT_DIR="/cert-exchange"
PRIVATE_KEY="$CERT_DIR/private-key.pem"
CSR="$CERT_DIR/csr.pem"
FINAL_CERT="$CERT_DIR/final-cert.pem"

if [ -f "$FINAL_CERT" ]; then
  echo "Certificate already exists at $FINAL_CERT — skipping issuance."
elif [ -f "$CSR" ]; then
  echo "CSR exists but no final cert — waiting for issuance to complete."
else
  echo "No certificate found. Generating private key and CSR..."
  openssl req -out "$CSR" -new -newkey rsa:2048 -nodes -keyout "$PRIVATE_KEY" \
    -subj "/C=GB/ST=UK/O=Webfront/OU=Webfront/CN=container/emailAddress=nobody@nowhere"
  chmod 600 "$PRIVATE_KEY"
  echo "CSR generated at $CSR"
fi

exec "$@"
