FROM openclaw-base:local

ARG BUILD_WITH_AWS=false

USER root

# ─── Homebrew (required for skill installation) ─────────────────────────────────
RUN useradd -m -s /bin/bash linuxbrew && \
    echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers

USER linuxbrew
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"

USER root
RUN chown -R linuxbrew:linuxbrew /home/linuxbrew/.linuxbrew && \
    chmod -R g+rwX /home/linuxbrew/.linuxbrew && \
    usermod -a -G linuxbrew node

RUN git config --global --add safe.directory /home/linuxbrew/.linuxbrew/Homebrew

# ─── AWS Components (conditional) ───────────────────────────────────────────────

# Certificate installation - copy files first, then conditionally install
COPY container-mounts/cert-exchange/root-ca-cert.pem /tmp/root-ca-cert.pem
COPY container-mounts/cert-exchange/app-cert.pem /tmp/app-cert.pem
COPY container-mounts/cert-exchange/app-key.pem /tmp/app-key.pem

RUN if [ "$BUILD_WITH_AWS" = "true" ]; then \
      echo "Installing AWS certificates..." && \
      # Import and trust root CA cert (.crt extension required by update-ca-certificates on Debian)
      cp /tmp/root-ca-cert.pem /usr/local/share/ca-certificates/root-ca-cert.crt && \
      update-ca-certificates && \
      # Copy app certificate and key (baked in at build time)
      mkdir -p /certs && chmod 700 /certs && \
      cp /tmp/app-cert.pem /certs/app-cert.pem && \
      cp /tmp/app-key.pem /certs/app-key.pem && \
      chmod 600 /certs/app-key.pem && \
      chown -R node:node /certs; \
    fi && \
    # Clean up temp files regardless of AWS mode
    rm -f /tmp/root-ca-cert.pem /tmp/app-cert.pem /tmp/app-key.pem

# Install AWS CLI v2
RUN if [ "$BUILD_WITH_AWS" = "true" ]; then \
      echo "Installing AWS CLI v2..." && \
      ARCH=$(uname -m) && \
      curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "/tmp/awscliv2.zip" && \
      unzip /tmp/awscliv2.zip -d /tmp && \
      /tmp/aws/install && \
      rm -rf /tmp/aws /tmp/awscliv2.zip; \
    fi

# Download aws_signing_helper for the correct architecture
ARG AWS_SIGNING_HELPER_VERSION=1.7.3
RUN if [ "$BUILD_WITH_AWS" = "true" ]; then \
      echo "Installing aws_signing_helper..." && \
      ARCH=$(uname -m) && \
      if [ "$ARCH" = "x86_64" ]; then HELPER_ARCH="X86_64"; \
      elif [ "$ARCH" = "aarch64" ]; then HELPER_ARCH="Aarch64"; \
      else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
      curl -o /usr/local/bin/aws_signing_helper \
        "https://rolesanywhere.amazonaws.com/releases/${AWS_SIGNING_HELPER_VERSION}/${HELPER_ARCH}/Linux/Amzn2023/aws_signing_helper" && \
      chmod +x /usr/local/bin/aws_signing_helper; \
    fi

# AWS config - copy to temp first, then conditionally install
COPY container-injects/config /tmp/aws-config

RUN if [ "$BUILD_WITH_AWS" = "true" ]; then \
      echo "Installing AWS config..." && \
      mkdir -p /home/node/.aws && \
      cp /tmp/aws-config /home/node/.aws/config && \
      chown -R node:node /home/node/.aws; \
    fi && \
    # Clean up temp file regardless of AWS mode
    rm -f /tmp/aws-config

# ─── Entrypoint ─────────────────────────────────────────────────────────────────
COPY container-injects/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ─── Security: non-root user ────────────────────────────────────────────────────
USER node

ENV PNPM_HOME=/home/node/.local/bin
ENV PATH=${PNPM_HOME}:${PATH}
ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
