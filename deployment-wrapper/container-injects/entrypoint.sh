#!/bin/bash
set -e

# Only validate AWS certs if AWS CLI is installed (indicates AWS mode)
if command -v aws &>/dev/null; then
  APP_CERT="/certs/app-cert.pem"
  APP_KEY="/certs/app-key.pem"

  if [ -f "$APP_CERT" ] && [ -f "$APP_KEY" ]; then
    echo "App certificate and key found — ready for AWS authentication."
  else
    echo "Error: AWS mode detected but certificate files missing from /certs/."
    [ ! -f "$APP_CERT" ] && echo "  Missing: $APP_CERT"
    [ ! -f "$APP_KEY" ] && echo "  Missing: $APP_KEY"
    exit 1
  fi
fi

exec "$@"
