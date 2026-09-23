#
# Dockerfile for squid
#

FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y squid-openssl openssl ca-certificates gosu \
    && rm -rf /var/lib/apt/lists/* \
    && squid --version

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
