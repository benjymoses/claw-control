FROM alpine/openssl:3.5.5

# Copy CA scripts
RUN mkdir -p /scripts
COPY containers/root-ca/init-ca.sh /scripts/init-ca.sh
COPY containers/root-ca/sign-cert.sh /scripts/sign-cert.sh
RUN chmod +x /scripts/init-ca.sh /scripts/sign-cert.sh

ENTRYPOINT []
CMD ["/bin/sh"]
