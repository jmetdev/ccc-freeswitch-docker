# syntax=docker/dockerfile:1

FROM debian:trixie-slim AS base

ARG FREESWITCH_VERSION="v1.11.1"
ARG SOFIA_VERSION="v1.13.17"
ARG SPANDSP_COMMIT="d9681c3747ff4f56b1876557b9f6d894b7e6c18d~1"

ENV DEBIAN_FRONTEND=noninteractive

FROM base AS deps

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${FREESWITCH_VERSION}" https://github.com/signalwire/freeswitch /freeswitch \
  && rm -rf /freeswitch/.git \
  && git clone --depth 1 --branch "${SOFIA_VERSION}" https://github.com/freeswitch/sofia-sip /libdeps/sofia-sip \
  && rm -rf /libdeps/sofia-sip/.git \
  && git clone https://github.com/freeswitch/spandsp /libdeps/spandsp \
  && cd /libdeps/spandsp \
  && git checkout "${SPANDSP_COMMIT}" \
  && rm -rf .git


FROM base AS builder-sofia

COPY --from=deps /libdeps/sofia-sip ./libdeps/sofia-sip
COPY patches/sofia-sip/. ./patches

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    libtool-bin \
    pkg-config \
    libssl-dev \
    libglib2.0-dev \
    libsctp-dev \
  && rm -rf /var/lib/apt/lists/*

RUN cd ./libdeps/sofia-sip \
  && for i in /patches/*.patch; do [ -f "$i" ] && patch -p1 < "$i" || true; done \
  && ./bootstrap.sh \
  && ./configure --prefix=/usr --enable-sctp --with-openssl --without-doxygen --enable-static=no \
  && make -j"$(nproc)" \
  && make DESTDIR=/build install


FROM base AS builder-spandsp

COPY --from=deps /libdeps/spandsp ./libdeps/spandsp

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    libtool-bin \
    pkg-config \
    libtiff-dev \
    libjpeg-dev \
  && rm -rf /var/lib/apt/lists/*

RUN cd ./libdeps/spandsp \
  && ./bootstrap.sh \
  && ./configure --prefix=/usr \
  && make -j"$(nproc)" \
  && make DESTDIR=/build install


FROM base AS builder-freeswitch

COPY --from=deps /freeswitch/ ./app
COPY build/modules.conf.in ./app/build/modules.conf.in
COPY --from=builder-sofia /build/. .
COPY --from=builder-spandsp /build/. .
COPY patches/freeswitch/. ./patches

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    libtool-bin \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    libpcre2-dev \
    libspeex-dev \
    libspeexdsp-dev \
    libedit-dev \
    libldns-dev \
    libjpeg-dev \
    libtiff-dev \
    libopus-dev \
    libsndfile1-dev \
    libbcg729-dev \
    libopencore-amrnb-dev \
    libopencore-amrwb-dev \
    uuid-dev \
    python3-dev \
    python3-setuptools \
    nasm \
    yasm \
    diffutils \
  && rm -rf /var/lib/apt/lists/*

RUN cd /app \
  && patch -p1 < /patches/disable-Werror.patch \
  && ./bootstrap.sh -j \
  && ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --enable-fhs \
    --with-scriptdir=/etc/freeswitch/scripts \
    --with-rundir=/run/freeswitch \
    --with-logfiledir=/var/log/freeswitch \
    --with-dbdir=/var/spool/freeswitch/db \
    --with-certsdir=/etc/freeswitch/certs \
    --with-python3 \
    --enable-zrtp \
  && make -j"$(nproc)" \
  && make install \
  && make DESTDIR=/build install \
  && ldd "$(which freeswitch)" | awk '/=>/ {print $3}' | grep -v '^$' | sort -u | xargs tar --dereference -cf /build/libs.tar


FROM base AS runner

ARG WORKER_USER_ID=499

COPY --from=builder-freeswitch /build/. .
COPY config/ /etc/freeswitch.default/
COPY config/fs_cli.conf /etc/fs_cli.conf
COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh

RUN groupadd -g "${WORKER_USER_ID}" freeswitch \
  && useradd -u "${WORKER_USER_ID}" -g freeswitch -d /var/lib/freeswitch -s /usr/sbin/nologin -M freeswitch \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    libopus0 \
    libsndfile1 \
    libspeex1 \
    libspeexdsp1 \
    libedit2 \
    libldns3 \
    libjpeg62-turbo \
    libtiff6 \
    libbcg729-0 \
    libopencore-amrnb0 \
    libopencore-amrwb0 \
    libsqlite3-0 \
    libcurl4t64 \
    libpcre2-8-0 \
    zlib1g \
    python3 \
  && tar -xf libs.tar -C / \
  && rm libs.tar \
  && chmod +x /docker-entrypoint.sh \
  && mkdir -p \
    /etc/freeswitch \
    /var/log/freeswitch \
    /var/lib/freeswitch/recordings \
    /var/spool/fax \
    /run/freeswitch \
    /usr/share/freeswitch/sounds/music/8000 \
  && chown -R freeswitch:freeswitch \
    /var/log/freeswitch \
    /var/lib/freeswitch \
    /var/spool/fax \
    /run/freeswitch \
  && rm -rf /var/lib/apt/lists/*

EXPOSE 8021/tcp
EXPOSE 5060/tcp 5060/udp 5080/tcp 5080/udp
EXPOSE 5061/tcp 5081/tcp
EXPOSE 16384-32768/udp

HEALTHCHECK --interval=15s --timeout=5s \
  CMD fs_cli -x status | grep -q ^UP || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/freeswitch", "-nonat", "-nf"]
