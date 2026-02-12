#!/bin/sh
set -e

CA_KEY="/mnt/root-ca-private-key/ca-key.pem"
CA_CERT="/mnt/cert-exchange/root-ca-cert.pem"

if [ -f "$CA_KEY" ]; then
  echo "CA key pair already exists, skipping generation."
  # Ensure public cert is in cert-exchange
  if [ ! -f "$CA_CERT" ]; then
    echo "Public cert missing from cert-exchange, regenerating from existing key..."
    cat > /tmp/ca-ext.cnf <<EOF
[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
EOF
    openssl req -new -x509 -key "$CA_KEY" \
      -out "$CA_CERT" -days 3650 \
      -subj "/C=GB/ST=UK/O=ClawControl/OU=CA/CN=ClawControl Root CA" \
      -extensions v3_ca -config /tmp/ca-ext.cnf
    rm -f /tmp/ca-ext.cnf
    echo "Root CA public certificate restored to $CA_CERT"
  fi
else
  echo "Generating new Root CA key pair..."
  openssl genrsa -out "$CA_KEY" 4096
  chmod 600 "$CA_KEY"

  # Create extensions config for AWS Roles Anywhere compatibility
  cat > /tmp/ca-ext.cnf <<EOF
[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
EOF

  openssl req -new -x509 -key "$CA_KEY" \
    -out "$CA_CERT" -days 3650 \
    -subj "/C=GB/ST=UK/O=ClawControl/OU=CA/CN=ClawControl Root CA" \
    -extensions v3_ca -config /tmp/ca-ext.cnf

  rm -f /tmp/ca-ext.cnf

  echo "Root CA key pair generated."
  echo "  Private key: $CA_KEY"
  echo "  Public cert: $CA_CERT"
fi
