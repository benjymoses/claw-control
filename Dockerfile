FROM node:22-bookworm

RUN corepack enable

# Setup certificate working folder
RUN mkdir -p /cert-exchange && chown node:node /cert-exchange && chmod 700 /cert-exchange

# Import and trust root CA cert
COPY ./aws/root-ca-body.pem /usr/local/share/ca-certificates/root-ca-body.crt
#RUN sudo update-ca-certificates
RUN update-ca-certificates

# Create certificate check entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Install AWS CLI
RUN ARCH=$(uname -m) \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "/tmp/awscliv2.zip" \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Configure AWS CLI and sign-in helper
RUN mkdir -p /home/node/.aws && chown -R node:node /home/node/.aws
COPY aws/config /home/node/.aws/config

COPY aws/aws_signing_helper /usr/local/bin
RUN chmod +x /usr/local/bin/aws_signing_helper

# Back to the app installation
WORKDIR /app

COPY ./the-project/package.json ./the-project/pnpm-lock.yaml ./the-project/pnpm-workspace.yaml ./
#RUN pnpm install --frozen-lockfile

COPY ./the-project .
RUN pnpm build

ENV NODE_ENV=production

# Allow non-root user to write temp files during runtime/tests.
RUN chown -R node:node /app

USER node

# CMD ["node", "index.js"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]