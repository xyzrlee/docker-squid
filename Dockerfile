ARG ALPINE_VERSION=latest

FROM alpine:${ALPINE_VERSION}

ARG SQUID_VERSION

COPY entrypoint.sh /entrypoint.sh

RUN set -e \
    && apk update \
    && echo "========== Available squid versions ==========" \
    && apk search -e -v squid \
    && echo "==============================================" \
    && if ! echo "${SQUID_VERSION}" | grep -q -- '-r'; then \
         FULL_VERSION=$(apk search -e -v squid \
           | awk -v ver="${SQUID_VERSION}" '$1 ~ "^squid-" ver "-r[0-9]+$" {print $1}' \
           | sed 's/^squid-//' \
           | sort -V \
           | tail -1); \
         if [ -z "${FULL_VERSION}" ]; then \
           echo "Error: No package found matching squid ${SQUID_VERSION}"; \
           echo "Available versions:"; \
           apk search -e -v squid; \
           exit 1; \
         fi; \
         echo "Auto-resolved to latest: ${FULL_VERSION}"; \
         SQUID_VERSION="${FULL_VERSION}"; \
       fi \
    && apk add --no-cache "squid=${SQUID_VERSION}" su-exec \
    && echo "========== Squid version ==========" \
    && squid -v \
    && echo "========== OpenSSL support check ==========" \
    && squid -v | grep -q -i openssl \
    && echo "OpenSSL support: YES" \
    && echo "====================================" \
    && rm -rf \
        /var/cache/apk/* \
        /tmp/* \
        /var/tmp/* \
        /root/.cache \
        /usr/share/man/* \
        /usr/share/doc/* \
    && find /var/log -type f -exec truncate -s 0 {} \; \
    && mkdir -p /var/spool/squid /var/log/squid \
    && chown -R squid:squid /var/spool/squid /var/log/squid \
    && chmod +x /entrypoint.sh

USER root

ENTRYPOINT ["/entrypoint.sh"]
CMD ["-f", "/etc/squid/squid.conf", "-NYC"]

