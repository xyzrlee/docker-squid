ARG SQUID_VERSION
ARG UBUNTU_VERSION=latest

FROM ubuntu:${UBUNTU_VERSION} AS builder

ARG SQUID_VERSION

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
# 使用 GitHub Releases 下载
RUN wget -q https://github.com/squid-cache/squid/releases/download/SQUID_${SQUID_VERSION//./_}/squid-${SQUID_VERSION}.tar.gz \
    && tar -xzf squid-${SQUID_VERSION}.tar.gz \
    && cd squid-${SQUID_VERSION} \
    && ./configure \
        --prefix=/usr \
        --sysconfdir=/etc/squid \
        --localstatedir=/var \
        --libexecdir=/usr/lib/squid \
        --datadir=/usr/share/squid \
        --with-openssl \
        --enable-ssl-crtd \
        --enable-security-cert-validators=fake \
        --enable-storeio=ufs,aufs,diskd,rock \
        --enable-removal-policies=lru,heap \
        --enable-delay-pools \
        --enable-cache-digests \
        --enable-icap-client \
        --enable-follow-x-forwarded-for \
        --with-default-user=proxy \
        --with-swapdir=/var/spool/squid \
        --with-logdir=/var/log/squid \
        --with-pidfile=/run/squid.pid \
        --disable-translation \
        --disable-arch-native \
    && make -j$(nproc) \
    && make install \
    && strip /usr/sbin/squid /usr/lib/squid/* 2>/dev/null || true

FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && useradd -r -s /usr/sbin/nologin proxy 2>/dev/null || true

COPY --from=builder /usr/sbin/squid /usr/sbin/squid
COPY --from=builder /usr/lib/squid/security_file_certgen /usr/lib/squid/security_file_certgen
COPY --from=builder /usr/share/squid /usr/share/squid
COPY --from=builder /etc/squid /etc/squid

RUN mkdir -p /var/spool/squid /var/log/squid /run \
    && chown -R proxy:proxy /var/spool/squid /var/log/squid /run /etc/squid \
    && chmod 755 /usr/sbin/squid /usr/lib/squid/security_file_certgen

USER proxy

ENTRYPOINT ["squid"]
CMD ["-f", "/etc/squid/squid.conf", "-NYC"]

