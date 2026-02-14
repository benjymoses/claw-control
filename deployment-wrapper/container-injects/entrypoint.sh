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

# Homebrew package persistence via package list
BREW_PACKAGES_FILE="/home/node/.openclaw/homebrew/packages.txt"

# Install packages from the persisted list
if [ -f "$BREW_PACKAGES_FILE" ]; then
  echo "Installing Homebrew packages from saved list..."
  while IFS= read -r package; do
    # Skip empty lines and comments
    [[ -z "$package" || "$package" =~ ^# ]] && continue
    echo "  Installing $package..."
    brew install "$package" 2>/dev/null || echo "    (already installed or failed)"
  done < "$BREW_PACKAGES_FILE"
  echo "Homebrew packages installed."
fi

exec "$@"
