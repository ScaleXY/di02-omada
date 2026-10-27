#!/bin/bash
set -euo pipefail

OMADA_HOME=${OMADA_HOME:-/opt/tplink/EAPController}
PROPS="${OMADA_HOME}/properties/omada.properties"

# Optional: remap the omada user to match host volume ownership
PUID=${PUID:-508}
PGID=${PGID:-508}
if [ "$(id -g omada)" != "${PGID}" ]; then groupmod -o -g "${PGID}" omada; fi
if [ "$(id -u omada)" != "${PUID}" ]; then usermod -o -u "${PUID}" omada; fi

# Seed empty volumes with the files shipped in the package (without overwriting)
cp -an /opt/tplink/data.default/. "${OMADA_HOME}/data/"
cp -an /opt/tplink/properties.default/. "${OMADA_HOME}/properties/"
mkdir -p "${OMADA_HOME}/data/autobackup" "${OMADA_HOME}/logs" "${OMADA_HOME}/work"

# Ports can be overridden by env; note that after first setup the controller
# keeps its own port config (Settings > Controller) and these are ignored.
set_prop() {
    local key=$1 val=$2
    [ -n "${val}" ] || return 0
    # delete + append rather than sed-replace so values may contain any character
    grep -v "^${key}=" "${PROPS}" > "${PROPS}.tmp" || true
    printf '%s=%s\n' "${key}" "${val}" >> "${PROPS}.tmp"
    mv "${PROPS}.tmp" "${PROPS}"
}
set_prop manage.http.port   "${MANAGE_HTTP_PORT:-}"
set_prop manage.https.port  "${MANAGE_HTTPS_PORT:-}"
set_prop portal.http.port   "${PORTAL_HTTP_PORT:-}"
set_prop portal.https.port  "${PORTAL_HTTPS_PORT:-}"

# External MongoDB: MONGO_EXTERNAL=true and
# EAP_MONGOD_URI=mongodb://user:pass@host:27017/omada
# Otherwise the controller starts its bundled mongod on 127.0.0.1:27217.
if [ "${MONGO_EXTERNAL:-false}" = "true" ]; then
    if [ -z "${EAP_MONGOD_URI:-}" ]; then
        echo "MONGO_EXTERNAL=true requires EAP_MONGOD_URI" >&2
        exit 1
    fi
    set_prop mongo.external true
    set_prop eap.mongod.uri "${EAP_MONGOD_URI}"
else
    set_prop mongo.external false
fi

chown -R omada:omada "${OMADA_HOME}/data" "${OMADA_HOME}/logs" "${OMADA_HOME}/work" "${OMADA_HOME}/properties"

# Clean up stale pid/lock files left by an unclean shutdown
rm -f "${OMADA_HOME}/data/mongo.pid" "${OMADA_HOME}/data/db/mongod.lock"

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

echo "Starting Omada Controller ${OMADA_VERSION:-}"

cd "${OMADA_HOME}/lib"
exec gosu omada java \
    -server \
    -XX:MaxHeapFreeRatio=60 -XX:MinHeapFreeRatio=30 \
    -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath="${OMADA_HOME}/logs/java_heapdump.hprof" \
    -Djava.awt.headless=true \
    -Djdk.lang.Process.launchMechanism=vfork \
    ${JAVA_OPTS:-} \
    -cp "/usr/share/java/commons-daemon.jar:${OMADA_HOME}/lib/*:${OMADA_HOME}/properties" \
    com.tplink.smb.omada.starter.OmadaLinuxMain
