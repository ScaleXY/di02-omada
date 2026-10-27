# syntax=docker/dockerfile:1
#
# TP-Link Omada Software Controller
#
# The .deb's maintainer scripts expect systemd/init and try to start the
# service during install, so instead of `dpkg -i` we extract the payload and
# do the postinst steps (user, dirs, mongod link) by hand. The controller is
# run in the foreground by entrypoint.sh instead of through jsvc.

FROM ubuntu:22.04

ARG OMADA_VERSION=5.15.24.19
ARG OMADA_URL=https://static.tp-link.com/upload/software/2025/202508/20250802/omada_v5.15.24.19_linux_x64_20250724152622.deb
ARG OMADA_SHA256=e38e59fb429f4b33727679f3032abcb2b4308d93191429691317b4d26f65f525
# Omada 5.15 supports MongoDB >= 3.0 and < 8.1
ARG MONGO_MAJOR=7.0

ENV DEBIAN_FRONTEND=noninteractive \
    OMADA_HOME=/opt/tplink/EAPController \
    OMADA_VERSION=${OMADA_VERSION} \
    TZ=Etc/UTC

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg tzdata gosu net-tools \
        openjdk-17-jre-headless jsvc; \
    curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_MAJOR}.asc" \
        | gpg --dearmor -o /usr/share/keyrings/mongodb.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/mongodb.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/${MONGO_MAJOR} multiverse" \
        > /etc/apt/sources.list.d/mongodb-org.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends mongodb-org-server; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL -o /tmp/omada.deb "${OMADA_URL}"; \
    echo "${OMADA_SHA256}  /tmp/omada.deb" | sha256sum -c -; \
    dpkg-deb -x /tmp/omada.deb /tmp/omada; \
    mv /tmp/omada/opt/tplink /opt/tplink; \
    rm -rf /tmp/omada /tmp/omada.deb; \
    groupadd --system --gid 508 omada; \
    useradd --system --uid 508 --gid omada --home-dir "${OMADA_HOME}/data" --no-create-home --shell /usr/sbin/nologin omada; \
    chmod 755 "${OMADA_HOME}"/bin/*; \
    ln -sf "$(command -v mongod)" "${OMADA_HOME}/bin/mongod"; \
    mkdir -p "${OMADA_HOME}/logs" "${OMADA_HOME}/work"; \
    # Pristine copies used to seed empty volumes on first start
    cp -a "${OMADA_HOME}/data" /opt/tplink/data.default; \
    cp -a "${OMADA_HOME}/properties" /opt/tplink/properties.default; \
    chown -R omada:omada "${OMADA_HOME}/data" "${OMADA_HOME}/logs" "${OMADA_HOME}/work" "${OMADA_HOME}/properties"

COPY --chmod=755 entrypoint.sh /entrypoint.sh

WORKDIR ${OMADA_HOME}/lib

# 8088/8043  management HTTP/HTTPS
# 8843       portal HTTPS
# 27001/udp  app discovery
# 29810/udp  device discovery
# 29811-29816/tcp device management, adoption, upgrade, transfer, rtty
EXPOSE 8088 8043 8843 27001/udp 29810/udp 29811-29816

VOLUME ["/opt/tplink/EAPController/data", "/opt/tplink/EAPController/logs"]

HEALTHCHECK --start-period=5m --interval=30s --timeout=10s --retries=5 \
    CMD curl -fsS -o /dev/null "http://127.0.0.1:${MANAGE_HTTP_PORT:-8088}/actuator/linux/check" || exit 1

LABEL org.opencontainers.image.title="omada-controller" \
      org.opencontainers.image.version="${OMADA_VERSION}" \
      org.opencontainers.image.description="TP-Link Omada Software Controller ${OMADA_VERSION}"

ENTRYPOINT ["/entrypoint.sh"]
