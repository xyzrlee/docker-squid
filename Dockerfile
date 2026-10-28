ARG ALPINE_VERSION=latest

FROM alpine:${ALPINE_VERSION}

ARG SQUID_VERSION

COPY entrypoint.sh /entrypoint.sh

RUN apk update \
    && echo "========== Available squid versions ==========" \
    && apk search -v 'squid' \
    && echo "==============================================" \
    && apk add --no-cache squid=${SQUID_VERSION} su-exec \
    && echo "========== Squid version ==========" \
    && squid -v \
    && echo "========== OpenSSL support check ==========" \
    && squid -v | grep -q -i openssl \
    && echo "OpenSSL support: YES" \
    || (echo "OpenSSL support: NO" && exit 1) \
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

