# 🦞 claw-control 🔧

A wrapper and build system for [OpenClaw](https://github.com/openclaw/openclaw) that makes it easy to build and maintain a customised Docker service from the official OpenClaw source. It adds Tailscale networking for secure remote access and includes Homebrew to support OpenClaw skills that need system dependencies. Optional AWS IAM Roles Anywhere integration provides certificate-based authentication for services like Amazon Bedrock.

The key benefit: you can keep your customised image up to date from the source repository with easy rebuilds — no fork to maintain.

> **⚠️ Disclaimer:** OpenClaw is a third-party project and is not maintained by the author of claw-control. You are responsible for reviewing and validating the security of any code pulled from the OpenClaw repository before building and running it. This tool generates cryptographic keys and certificates — you are solely responsible for safeguarding any private keys and credentials produced. Do not commit them to version control or expose them publicly. Use at your own risk.

## ✨ What It Does

claw-control builds a customized OpenClaw Docker image by:

1. 🏗️ **Building the official OpenClaw container** from the upstream Dockerfile (unmodified)
2. 🎨 **Extending it with essential infrastructure**:
   - **🍺 Homebrew** — enables OpenClaw skills to install system dependencies
   - **🔐 Tailscale sidecar** — secure remote access via your Tailnet (just add your auth key to `.env`)
   - **☁️ AWS IAM Roles Anywhere** (optional) — certificate-based authentication for secure, dynamic access to Amazon Bedrock models

You always get the latest official OpenClaw build with no fork to maintain. The build system simply layers the infrastructure you need on top.

## 📋 Prerequisites

- 🐳 [Docker](https://docs.docker.com/get-docker/) or [Finch](https://github.com/runfinch/finch) (the script auto-detects which is available)
- 📦 [Git](https://git-scm.com/) for pulling OpenClaw source
- 🔐 **For Tailscale**: A Tailscale account and auth key (get one at https://login.tailscale.com/admin/settings/keys)
- ☁️ **For AWS (optional)**: 
  - [jq](https://jqlang.github.io/jq/) for JSON parsing (`brew install jq`)
  - (optional) [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) with authenticated profile (only needed for automatic Roles Anywhere setup)

## 🚀 Usage

```bash
./claw-control.sh
```

The interactive menu walks you through the workflow:

1. **Build from Latest OpenClaw Update** — pulls the latest OpenClaw source (or clones if needed), validates prerequisites, and builds both the base image from upstream and the overlay image with Homebrew and Tailscale support. If you're using AWS, prompts for any missing ARN values along the way.
2. **Compose Up** — starts all services (Tailscale sidecar, OpenClaw gateway, CLI) using Docker/Finch Compose.
3. **Compose Down** — safely stops all services while retaining data.
4. **🔐 Generate Certificates** (optional, AWS only) — sets up the offline Root CA and generates the app certificate needed for IAM Roles Anywhere. If certificates already exist, it will notify you and explain how to regenerate them. Only needs to be done once for initial setup.
5. **☁️ AWS Roles Anywhere Setup** (optional) — walks you through setting up the AWS-side requirements for IAM Roles Anywhere (trust anchor, profile, and role). Can run the commands for you or just show them. Note: the IAM role created has no permissions by default — you'll need to attach a policy manually. The script outputs a direct link to the role in the AWS console so you can do this easily. See the example Bedrock policy below.

### 🎯 Quick Start (No AWS)

If you just want OpenClaw with Homebrew and Tailscale:

1. Run `./claw-control.sh` and select option 1 (Build from Latest)
   - On first run, this generates `.env` from `.env.example` (if you're an existing OpenClaw user you can paste in the values from your old .env file here afterwards)
   - The script will automatically detect if you haven't generated certificates for AWS auth and build without AWS components
2. Add your Tailscale auth key to `.env`:
   ```bash
   # Option 1: Edit .env directly and add your key
   # TS_AUTHKEY=tskey-auth-xxxxx
   
   # Option 2: Use echo to append it
   echo "TS_AUTHKEY=tskey-auth-xxxxx" >> .env
   ```
3. Run `./claw-control.sh` again and select option 1 to rebuild with Tailscale configured
4. Select option 2 (Compose Up)

That's it! Access your gateway at:
- `https://openclaw-gateway.<your-tailnet>.ts.net/?token=paste-your-gateway-token`

(Find your gateway token in `.env` as `OPENCLAW_GATEWAY_TOKEN`)

### ☁️ With AWS Bedrock

If you want to use Amazon Bedrock models:

1. Run option 4 (Generate Certificates) to create the certificates
2. Run option 5 (AWS Roles Anywhere Setup) to configure AWS
3. Attach a Bedrock policy to the IAM role (see example below)
4. Run option 1 (Build from Latest)
   - The script will automatically detect AWS certificates and ARN values, building with AWS support
5. Run option 2 (Compose Up)

The build script automatically detects whether to include AWS components by checking:

1. **Certificate files exist**: root CA cert, app cert, and app key
2. **AWS config exists**: generated AWS CLI config file
3. **ARN values configured**: `TRUST_ANCHOR_ARN`, `PROFILE_ARN`, and `ROLE_ARN` in `.env` are not placeholders

If all conditions are met, the build includes AWS CLI, aws_signing_helper, and certificates. Otherwise, it builds a lighter image with just Homebrew and Tailscale support.

You can switch between modes at any time — just run the certificate and AWS setup options, then rebuild.

### 📜 Example: Bedrock access policy

The role created by the setup has no permissions. To grant access to Bedrock models, attach an inline policy like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAccess",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListFoundationModels"
      ],
      "Resource": "*"
    }
  ]
}
```

## 💡 Concepts

### 🔐 Tailscale Sidecar

The deployment uses a Tailscale sidecar container that provides secure networking:

- All services share the Tailscale container's network via `network_mode: "service:tailscale"`
- Automatic HTTPS via Tailscale Serve (no certificates to manage)
- Access from any device on your Tailnet
- No port forwarding or firewall configuration needed

Just add your `TS_AUTHKEY` to `.env` and you're ready to go.

### 🍺 Homebrew & Skill Persistence

OpenClaw skills often require system dependencies installed via Homebrew. claw-control persists Homebrew packages and skill configurations across container restarts by mounting host directories:

**What persists:**
- `~/.openclaw-brew/cellar/` — Installed Homebrew packages
- `~/.openclaw-brew/opt/` — Package symlinks
- `~/.openclaw-brew/var/` — Package metadata
- `~/.openclaw-brew/taps/` — Formula repositories
- `~/.openclaw-brew/config/` — Skill configurations (like `~/.config/gogcli`)

**Setup:**
Create the persistence directories before first run:
```bash
mkdir -p ~/.openclaw-brew/{cellar,opt,var,taps,config}
```

**How it works:**
- Install skills normally: `docker compose run --rm openclaw-cli skills install <skill-name>`
- On container restart, the entrypoint automatically reinstalls packages to recreate symlinks
- Skill configurations and credentials persist in `~/.openclaw-brew/config/`

**Skill-specific environment variables:**
Some skills require API keys or credentials. Add these to your `.env` file:
```bash
# Example: GOG skill
GOG_KEYRING_PASSWORD=your-password
GOG_ACCOUNT=your-email@example.com
```

The `OPENCLAW_BREW_DIR` variable in `.env` controls where these directories are stored (defaults to `~/.openclaw-brew`).

### ☁️ AWS IAM Roles Anywhere (Optional)

IAM Roles Anywhere provides a more secure alternative to hardcoding IAM User credentials. It lets workloads outside of AWS use X.509 certificates to obtain temporary AWS credentials with a 1-hour lifetime. This can be easily disabled centrally from your AWS account if needed.

**What the setup does:**

The AWS setup process (menu option 5) performs the following:

1. **Creates and activates a Trust Anchor** using the root CA certificate you generated
2. **Creates and activates a Profile** that links the trust anchor to an IAM role
3. **Creates an IAM role** named `OpenClawRolesAnywhereRole` to tie everything together

The role is created with no permissions by default — you must manually attach policies (like the Bedrock example above) to grant access to AWS services.

Inside the container, `aws_signing_helper` uses the baked-in certificates to assume the IAM role and obtain temporary credentials automatically.

> **⚠️ AWS Configuration Disclaimer:** I am not responsible for any AWS configuration performed by this tool. You use the AWS setup features at your own risk. Always validate the AWS configuration and review the IAM role before attaching any permissions to it. Ensure you understand the security implications of the policies you attach.

See [AWS docs](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/getting-started.html) for more info on IAM Roles Anywhere.

## 🤝 Contribution

Coming soon...
