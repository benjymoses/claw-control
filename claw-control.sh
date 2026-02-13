#!/bin/bash
set -euo pipefail

# ─── OS Detection ──────────────────────────────────────────────────────────────

# Detect OS for sed compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_INPLACE="sed -i ''"
else
  SED_INPLACE="sed -i"
fi

# Cross-platform sed in-place replacement
sed_replace() {
  local pattern="$1"
  local file="$2"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$pattern" "$file"
  else
    sed -i "$pattern" "$file"
  fi
}

# ─── Container CLI Detection ───────────────────────────────────────────────────

CONTAINER_CLI=""

detect_container_cli() {
  if command -v docker &>/dev/null; then
    CONTAINER_CLI="docker"
  elif command -v finch &>/dev/null; then
    CONTAINER_CLI="finch"
  else
    echo "Error: Neither Docker nor Finch found."
    echo "Please install one of:"
    echo "  Docker: https://docs.docker.com/get-docker/"
    echo "  Finch:  https://github.com/runfinch/finch"
    exit 1
  fi
  echo "Using container CLI: $CONTAINER_CLI"
}

# ─── Utilities ──────────────────────────────────────────────────────────────────

error_msg() {
  echo ""
  echo "Error: $1"
  echo ""
}

check_file_exists() {
  local file="$1"
  local description="${2:-$file}"
  if [ ! -f "$file" ]; then
    return 1
  fi
  return 0
}

# ─── .env Management ────────────────────────────────────────────────────────────

ENV_FILE=".env"
ENV_EXAMPLE=".env.example"
ARN_VARS=("TRUST_ANCHOR_ARN" "PROFILE_ARN" "ROLE_ARN")
PLACEHOLDER="paste-here"

is_placeholder() {
  local val="$1"
  [[ -z "$val" || "$val" == "$PLACEHOLDER" || "$val" == "<"*">" ]]
}

prompt_arn_value() {
  local var_name="$1"
  local current_val="${2:-}"
  if [ -n "$current_val" ] && ! is_placeholder "$current_val"; then
    echo "  $var_name = $current_val"
  fi
  read -rp "  Enter $var_name: " new_val
  if [ -n "$new_val" ]; then
    # Use | as sed delimiter since ARNs contain colons and slashes
    sed_replace "s|^${var_name}=.*|${var_name}=${new_val}|" "$ENV_FILE"
  fi
}

manage_env() {
  # Create .env from example if it doesn't exist
  if [ ! -f "$ENV_FILE" ]; then
    echo "No .env file found. Creating from $ENV_EXAMPLE..."
    cp "$ENV_EXAMPLE" "$ENV_FILE"
  fi

  # Source current values
  source "$ENV_FILE"

  # Check which values need populating
  local missing=()
  for var in "${ARN_VARS[@]}"; do
    local val="${!var:-}"
    if is_placeholder "$val"; then
      missing+=("$var")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    # All values populated — ask to reuse or re-enter
    echo ""
    echo "Current .env values:"
    for var in "${ARN_VARS[@]}"; do
      echo "  $var = ${!var}"
    done
    echo ""
    read -rp "Use these values? [Y/n]: " reuse
    if [[ "$reuse" =~ ^[Nn] ]]; then
      echo "Enter new values:"
      for var in "${ARN_VARS[@]}"; do
        prompt_arn_value "$var" "${!var}"
      done
    fi
  else
    # Prompt only for missing values
    echo ""
    echo "The following values need to be set:"
    for var in "${missing[@]}"; do
      prompt_arn_value "$var"
    done
  fi

  # Re-source to pick up any changes
  source "$ENV_FILE"
}

generate_aws_config() {
  local template="deployment-wrapper/container-injects/config.example"
  local output="deployment-wrapper/container-injects/config"

  source "$ENV_FILE"

  sed -e "s|<TRUST_ANCHOR_ARN>|${TRUST_ANCHOR_ARN}|g" \
      -e "s|<PROFILE_ARN>|${PROFILE_ARN}|g" \
      -e "s|<ROLE_ARN>|${ROLE_ARN}|g" \
      "$template" > "$output"

  echo "AWS config generated at $output"
}

# ─── Action Functions ───────────────────────────────────────────────────────────

init_ca() {
  echo "Initializing Root CA..."
  if $CONTAINER_CLI compose -f deployment-wrapper/containers/root-ca/compose.yaml run --rm --build root-ca /scripts/init-ca.sh; then
    echo ""
    echo "Root CA initialized successfully."
  else
    error_msg "Failed to initialize Root CA. Check the output above for details."
  fi
}

generate_app_cert() {
  if ! check_file_exists "deployment-wrapper/container-mounts/root-ca-private-key/ca-key.pem"; then
    error_msg "CA must be initialized first. Run option 1."
    return
  fi

  echo "Generating and signing app certificate..."
  if $CONTAINER_CLI compose -f deployment-wrapper/containers/root-ca/compose.yaml run --rm --build root-ca /scripts/sign-cert.sh; then
    echo ""
    echo "App certificate generated successfully."
    echo "Files in deployment-wrapper/container-mounts/cert-exchange/:"
    echo "  - app-key.pem"
    echo "  - app-cert.pem"
  else
    error_msg "Failed to generate app certificate. Check the output above for details."
  fi
}

generate_certificates() {
  local ca_key="deployment-wrapper/container-mounts/root-ca-private-key/ca-key.pem"
  local ca_cert="deployment-wrapper/container-mounts/cert-exchange/root-ca-cert.pem"
  local app_cert="deployment-wrapper/container-mounts/cert-exchange/app-cert.pem"
  local app_key="deployment-wrapper/container-mounts/cert-exchange/app-key.pem"

  # Check if all certificates already exist
  if check_file_exists "$ca_key" && check_file_exists "$ca_cert" && \
     check_file_exists "$app_cert" && check_file_exists "$app_key"; then
    echo ""
    echo "All certificates already exist:"
    echo "  - Root CA key and certificate"
    echo "  - App certificate and key"
    echo ""
    echo "To regenerate certificates, manually delete the relevant files and re-run this option:"
    echo "  - CA certs: deployment-wrapper/container-mounts/root-ca-private-key/ca-key.pem"
    echo "              deployment-wrapper/container-mounts/cert-exchange/root-ca-cert.pem"
    echo "  - App certs: deployment-wrapper/container-mounts/cert-exchange/app-cert.pem"
    echo "               deployment-wrapper/container-mounts/cert-exchange/app-key.pem"
    echo ""
    return
  fi

  # Run CA initialization (has its own safety checks)
  echo "Initializing Root CA..."
  if $CONTAINER_CLI compose -f deployment-wrapper/containers/root-ca/compose.yaml run --rm --build root-ca /scripts/init-ca.sh; then
    echo ""
    echo "Root CA initialized successfully."
  else
    error_msg "Failed to initialize Root CA. Check the output above for details."
    return
  fi

  # Run app certificate generation (has its own safety checks)
  echo ""
  echo "Generating and signing app certificate..."
  if $CONTAINER_CLI compose -f deployment-wrapper/containers/root-ca/compose.yaml run --rm --build root-ca /scripts/sign-cert.sh; then
    echo ""
    echo "App certificate generated successfully."
    echo ""
    echo "Certificate generation complete. Files created:"
    echo "  - deployment-wrapper/container-mounts/root-ca-private-key/ca-key.pem"
    echo "  - deployment-wrapper/container-mounts/cert-exchange/root-ca-cert.pem"
    echo "  - deployment-wrapper/container-mounts/cert-exchange/app-cert.pem"
    echo "  - deployment-wrapper/container-mounts/cert-exchange/app-key.pem"
  else
    error_msg "Failed to generate app certificate. Check the output above for details."
  fi
}

build_from_latest() {
  local repo_url="https://github.com/openclaw/openclaw"
  local target_dir="openclaw"

  # ── Step 1: Ensure openclaw/ source exists ──
  if [ -d "$target_dir/.git" ]; then
    # Check for uncommitted changes
    if ! git -C "$target_dir" diff --quiet 2>/dev/null || ! git -C "$target_dir" diff --cached --quiet 2>/dev/null; then
      echo ""
      echo "Warning: openclaw/ has uncommitted changes."
      read -rp "Proceed with git pull anyway? [y/N]: " confirm
      if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Aborted."
        return
      fi
    fi
    echo "Updating existing OpenClaw clone..."
    if ! git -C "$target_dir" pull; then
      error_msg "Failed to pull latest OpenClaw. Check the output above."
      return
    fi
  elif [ -d "$target_dir" ]; then
    error_msg "$target_dir exists but is not a git repository. Remove it and try again."
    return
  else
    echo "Cloning OpenClaw..."
    if ! git clone "$repo_url" "$target_dir"; then
      error_msg "Failed to clone OpenClaw. Check the output above."
      return
    fi
  fi

  local commit
  commit=$(git -C "$target_dir" rev-parse --short HEAD)
  echo "OpenClaw at commit: $commit"

  # ── Step 2: Ensure .env exists (create from example if needed) ──
  if [ ! -f "$ENV_FILE" ]; then
    echo ""
    echo "No .env file found. Creating from $ENV_EXAMPLE..."
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Please edit .env with your Tailscale auth key and other settings."
    echo ""
  fi

  # ── Step 3: Detect if AWS mode is desired ──
  local build_with_aws="false"
  
  # Check for certificate files
  if check_file_exists "deployment-wrapper/container-mounts/cert-exchange/root-ca-cert.pem" && \
     check_file_exists "deployment-wrapper/container-mounts/cert-exchange/app-cert.pem" && \
     check_file_exists "deployment-wrapper/container-mounts/cert-exchange/app-key.pem" && \
     check_file_exists "deployment-wrapper/container-injects/config"; then
    
    # Also check that ARN values are populated in .env
    source "$ENV_FILE"
    if ! is_placeholder "${TRUST_ANCHOR_ARN:-}" && \
       ! is_placeholder "${PROFILE_ARN:-}" && \
       ! is_placeholder "${ROLE_ARN:-}"; then
      build_with_aws="true"
      echo ""
      echo "✓ AWS certificates and configuration detected"
      echo "  Building with AWS IAM Roles Anywhere support"
      echo ""
    else
      echo ""
      echo "AWS certificates found but ARN values not configured in .env"
      echo "Building without AWS support. Run option 5 to configure AWS."
      echo ""
    fi
  else
    echo ""
    echo "No AWS certificates detected — building without AWS support"
    echo "(Run options 4 and 5 if you want AWS Bedrock access)"
    echo ""
  fi

  # Only manage env and generate AWS config if building with AWS
  if [ "$build_with_aws" = "true" ]; then
    manage_env
    generate_aws_config
  fi

  # ── Step 4: Build base image from upstream Dockerfile ──
  echo ""
  echo "Building base image (openclaw-base:local) from upstream Dockerfile..."
  if ! $CONTAINER_CLI build -t openclaw-base:local -f ./openclaw/Dockerfile ./openclaw/; then
    error_msg "Base image build failed. Check the output above."
    return
  fi
  echo "Base image built successfully."

  # ── Step 5: Build overlay image with claw-control customizations ──
  echo ""
  if [ "$build_with_aws" = "true" ]; then
    echo "Building overlay image (openclaw:local) with Homebrew, Tailscale, and AWS support..."
  else
    echo "Building overlay image (openclaw:local) with Homebrew and Tailscale support..."
  fi
  
  if ! $CONTAINER_CLI build \
    --build-arg BUILD_WITH_AWS="$build_with_aws" \
    -t openclaw:local \
    -f deployment-wrapper/containers/claw-builder/Dockerfile \
    deployment-wrapper/; then
    error_msg "Overlay image build failed. Check the output above."
    return
  fi
  
  echo ""
  echo "Build complete. openclaw:local is ready."
  
  if [ "$build_with_aws" = "false" ]; then
    echo ""
    echo "Tip: To enable AWS Bedrock access later, run options 4 and 5, then rebuild."
  fi
}

compose_up() {
  echo "Starting services..."
  if $CONTAINER_CLI compose -f compose.yaml up -d; then
    echo ""
    echo "Services started. Use '$CONTAINER_CLI compose -f compose.yaml logs -f' to view logs."
  else
    error_msg "Failed to start services. Check the output above."
  fi
}

compose_down() {
  echo "Stopping services..."
  if $CONTAINER_CLI compose -f compose.yaml down; then
    echo ""
    echo "Services stopped."
  else
    error_msg "Failed to stop services. Check the output above."
  fi
}

aws_roles_anywhere_setup() {
  local ca_cert="deployment-wrapper/container-mounts/cert-exchange/root-ca-cert.pem"
  local region="eu-west-1"

  if ! check_file_exists "$ca_cert"; then
    error_msg "CA must be initialized first. Run option 1."
    return
  fi

  if ! command -v jq &>/dev/null; then
    error_msg "jq is required for AWS setup. Install it with: brew install jq"
    return
  fi

  echo ""
  echo "AWS IAM Roles Anywhere Setup"
  echo ""
  echo "  1) Automatic — run AWS CLI commands and capture ARNs"
  echo "  2) Manual — display commands for you to run yourself"
  echo ""
  read -rp "Select mode [1/2]: " mode

  case "$mode" in
    1) _aws_setup_automatic "$ca_cert" "$region" ;;
    2) _aws_setup_manual "$ca_cert" "$region" ;;
    *) error_msg "Invalid selection. Choose 1 or 2." ;;
  esac
}

_aws_setup_automatic() {
  local ca_cert="$1"
  local region="$2"
  local result

  # Ensure .env exists
  if [ ! -f "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
  fi

  # 1. Create trust anchor
  echo ""
  echo "Creating trust anchor..."
  local cert_data
  cert_data=$(cat "$ca_cert")
  local ta_cmd="aws rolesanywhere create-trust-anchor --name claw-control-ca --source sourceType=CERTIFICATE_BUNDLE,sourceData={x509CertificateData=\"${cert_data}\"} --region $region --output json"

  if result=$(eval "$ta_cmd" 2>&1); then
    local trust_anchor_arn
    trust_anchor_arn=$(echo "$result" | jq -r '.trustAnchor.trustAnchorArn')
    echo "  Trust Anchor ARN: $trust_anchor_arn"
    sed_replace "s|^TRUST_ANCHOR_ARN=.*|TRUST_ANCHOR_ARN=${trust_anchor_arn}|" "$ENV_FILE"

    # Enable the trust anchor
    echo "  Enabling trust anchor..."
    if ! aws rolesanywhere enable-trust-anchor --trust-anchor-id "$(echo "$trust_anchor_arn" | awk -F'/' '{print $NF}')" --region "$region" > /dev/null 2>&1; then
      error_msg "Trust anchor created but failed to enable. You may need to enable it manually in the console."
    else
      echo "  Trust anchor enabled."
    fi
  else
    error_msg "Failed to create trust anchor."
    echo "Command was:"
    echo "  $ta_cmd"
    echo ""
    echo "Error output:"
    echo "  $result"
    return
  fi

  # 2. Create IAM role with trust policy
  echo ""
  echo "Creating IAM role..."
  local trust_policy
  trust_policy=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rolesanywhere.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession",
        "sts:SetSourceIdentity"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/x509Issuer/CN": "ClawControl Root CA"
        }
      }
    }
  ]
}
EOF
)
  local role_cmd="aws iam create-role --role-name claw-control-role --assume-role-policy-document '${trust_policy}' --max-session-duration 28800 --region $region --output json"

  if result=$(eval "$role_cmd" 2>&1); then
    local role_arn
    role_arn=$(echo "$result" | jq -r '.Role.Arn')
    echo "  Role ARN: $role_arn"
    sed_replace "s|^ROLE_ARN=.*|ROLE_ARN=${role_arn}|" "$ENV_FILE"
  else
    error_msg "Failed to create IAM role."
    echo "Command was:"
    echo "  $role_cmd"
    echo ""
    echo "Error output:"
    echo "  $result"
    return
  fi

  # 3. Create profile
  echo ""
  echo "Creating Roles Anywhere profile..."
  local profile_cmd="aws rolesanywhere create-profile --name claw-control-profile --role-arns $role_arn --region $region --output json"

  if result=$(eval "$profile_cmd" 2>&1); then
    local profile_arn
    profile_arn=$(echo "$result" | jq -r '.profile.profileArn')
    echo "  Profile ARN: $profile_arn"
    sed_replace "s|^PROFILE_ARN=.*|PROFILE_ARN=${profile_arn}|" "$ENV_FILE"

    # Enable the profile
    echo "  Enabling profile..."
    if ! aws rolesanywhere enable-profile --profile-id "$(echo "$profile_arn" | awk -F'/' '{print $NF}')" --region "$region" > /dev/null 2>&1; then
      error_msg "Profile created but failed to enable. You may need to enable it manually in the console."
    else
      echo "  Profile enabled."
    fi
  else
    error_msg "Failed to create Roles Anywhere profile."
    echo "Command was:"
    echo "  $profile_cmd"
    echo ""
    echo "Error output:"
    echo "  $result"
    return
  fi

  echo ""
  echo "AWS Roles Anywhere setup complete. ARN values saved to .env"
  echo ""
  echo "  ℹ️ The IAM role has no permissions by default."
  echo "  Add a policy in the AWS console:"
  echo "  https://console.aws.amazon.com/iam/home#/roles/claw-control-role"
  echo ""
  echo "  For Bedrock access, attach an inline policy with:"
  echo "    - bedrock:InvokeModel"
  echo "    - bedrock:InvokeModelWithResponseStream"
  echo "    - bedrock:ListFoundationModels"
}

_aws_setup_manual() {
  local ca_cert="$1"
  local region="$2"

  echo ""
  echo "Run the following commands and copy the ARN values into your .env file:"
  echo ""
  echo "1. Create a trust anchor:"
  echo "   aws rolesanywhere create-trust-anchor \\"
  echo "     --name claw-control-ca \\"
  echo "     --source \"sourceType=CERTIFICATE_BUNDLE,sourceData={x509CertificateData=\$(cat $ca_cert)}\" \\"
  echo "     --region $region"
  echo ""
  echo "   Copy the trustAnchorArn value to TRUST_ANCHOR_ARN in .env"
  echo ""
  echo "2. Create an IAM role with a Roles Anywhere trust policy:"
  echo "   aws iam create-role \\"
  echo "     --role-name claw-control-role \\"
  echo "     --assume-role-policy-document file://trust-policy.json \\"
  echo "     --region $region"
  echo ""
  echo "   (See AWS docs for the trust policy JSON format)"
  echo "   Copy the Role.Arn value to ROLE_ARN in .env"
  echo ""
  echo "3. Create a Roles Anywhere profile:"
  echo "   aws rolesanywhere create-profile \\"
  echo "     --name claw-control-profile \\"
  echo "     --role-arns <ROLE_ARN from step 2> \\"
  echo "     --region $region"
  echo ""
  echo "   Copy the profile.profileArn value to PROFILE_ARN in .env"
  echo ""
  echo "Note: The IAM role created above has no permissions by default."
  echo "You will need to attach a policy granting the access you need (e.g. Bedrock)."
  echo "See the README for an example inline policy."
  echo ""
}

# ─── Menu ───────────────────────────────────────────────────────────────────────

show_menu() {
  echo ""
  echo "╔═══════════════════════════╗"
  echo "║   🦞 claw-control 🦞  🔧  ║"
  echo "╚═══════════════════════════╝"
  echo ""
  echo "  1) Build from Latest OpenClaw Update"
  echo "  2) Compose Up"
  echo "  3) Compose Down"
  echo "  4) Generate Certificates (optional: AWS)"
  echo "  5) AWS Roles Anywhere Setup (optional: AWS)"
  echo ""
  echo "  x) Exit"
  echo ""
}

# ─── Main Loop ──────────────────────────────────────────────────────────────────

detect_container_cli

while true; do
  show_menu
  read -rp "Select an option [1-5, x]: " choice

  case "$choice" in
    1) build_from_latest ;;
    2) compose_up ;;
    3) compose_down ;;
    4) generate_certificates ;;
    5) aws_roles_anywhere_setup ;;
    x|X) echo "Goodbye."; exit 0 ;;
    *)
      error_msg "Invalid option '$choice'. Please select 1-5 or x."
      ;;
  esac
done
