#!/bin/sh
set -e

CA_KEY="/mnt/root-ca-private-key/ca-key.pem"
CA_CERT="/mnt/cert-exchange/root-ca-cert.pem"
APP_KEY="/mnt/cert-exchange/app-key.pem"
APP_CERT="/mnt/cert-exchange/app-cert.pem"

if [ ! -f "$CA_KEY" ]; then
  echo "Error: CA not initialized. Run init-ca.sh first."
  exit 1
fi

if [ ! -f "$CA_CERT" ]; then
  echo "Error: Root CA certificate not found at $CA_CERT"
  exit 1
fi

echo "Generating app private key..."
openssl genrsa -out "$APP_KEY" 2048
chmod 600 "$APP_KEY"

echo "Creating CSR..."
openssl req -new -key "$APP_KEY" \
  -out /tmp/app-csr.pem \
  -subj "/C=GB/ST=UK/O=ClawControl/OU=App/CN=claw-app"

echo "Signing CSR with Root CA..."

# Create v3 extensions for the app cert (AWS Roles Anywhere requires v3)
cat > /tmp/app-ext.cnf <<EOF
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

openssl x509 -req -in /tmp/app-csr.pem \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial -out "$APP_CERT" -days 365 \
  -extfile /tmp/app-ext.cnf

rm -f /tmp/app-csr.pem /tmp/app-ext.cnf

echo "App certificate generated and signed."
echo "  Private key: $APP_KEY"
echo "  Certificate: $APP_CERT"
