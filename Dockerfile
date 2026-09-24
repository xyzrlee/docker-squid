#
# squid-openssl image for SSL bump.
# CA material is supplied at runtime (see entrypoint.sh); it is not baked in.
#
FROM ubuntu:26.04

LABEL org.opencontainers.image.title="squid" \
      org.opencontainers.image.description="Ubuntu squid-openssl with SSL-bump helpers" \
      org.opencontainers.image.source="https://github.com/xyzrlee/docker-squid" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    SQUID_CERT_DIR=/etc/squid/ssl_cert \
    SQUID_DB_DIR=/var/lib/squid/ssl_db \
    SQUID_CONF=/etc/squid/squid.conf \
    SQUID_USER=proxy \
    SQUID_GROUP=proxy

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        squid-openssl \
        openssl \
        ca-certificates \
        gosu \
    && rm -rf /var/lib/apt/lists/* \
    && squid --version \
    && mkdir -p "${SQUID_CERT_DIR}" "${SQUID_DB_DIR}" /var/log/squid /var/spool/squid \
    && chown -R proxy:proxy \
        "${SQUID_CERT_DIR}" \
        "${SQUID_DB_DIR}" \
        /var/log/squid \
        /var/spool/squid \
        /etc/squid \
    && chmod 0750 "${SQUID_CERT_DIR}"

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

# Squid answers cache manager on the HTTP port when running; keep the check cheap.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD squidclient -h 127.0.0.1 -p 3128 mgr:info >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
