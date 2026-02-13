#!/bin/bash
set -e

# Configure git to trust Homebrew directory
git config --global --add safe.directory /home/linuxbrew/.linuxbrew/Homebrew 2>/dev/null || true

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

# Relink Homebrew packages from persisted Cellar
# This recreates symlinks in bin/ for packages that were installed previously
if [ -d "/home/linuxbrew/.linuxbrew/Cellar" ]; then
  echo "Relinking Homebrew packages..."
  for formula in /home/linuxbrew/.linuxbrew/Cellar/*; do
    if [ -d "$formula" ]; then
      formula_name=$(basename "$formula")
      echo "  Reinstalling $formula_name..."
      brew reinstall "$formula_name" 2>/dev/null || true
    fi
  done
  echo "Homebrew packages relinked."
fi

exec "$@"
