#!/usr/bin/env bash
# Apply SIP port 5070 (external/trunk) on a deployed ccc-freeswitch host.
# Usage: ./scripts/configure-sip-5070.sh [freeswitch-conf-dir]

set -euo pipefail

CONF_DIR="${1:-./freeswitch-conf}"
CONTAINER="${CONTAINER:-ccc-freeswitch}"

if [ ! -d "${CONF_DIR}" ]; then
  echo "Config dir not found: ${CONF_DIR}" >&2
  exit 1
fi

ts="$(date +%Y%m%d%H%M%S)"
cp -a "${CONF_DIR}/vars.xml" "${CONF_DIR}/vars.xml.bak.${ts}"

set_var() {
  local name="$1" value="$2" file="${CONF_DIR}/vars.xml"
  if grep -q "name=\"${name}\"" "$file"; then
    sed -i "s/name=\"${name}\" value=\"[^\"]*\"/name=\"${name}\" value=\"${value}\"/" "$file"
  else
    sed -i "/<include>/a\\  <X-PRE-PROCESS cmd=\"set\" data=\"${name}=${value}\"/>" "$file"
  fi
}

set_var external_sip_port 5070
set_var external_tls_port 5071
set_var internal_sip_port 5060
set_var internal_tls_port 5061

for profile in external internal; do
  f="${CONF_DIR}/sip_profiles/${profile}.xml"
  [ -f "$f" ] || continue
  cp -a "$f" "${f}.bak.${ts}"
done

if [ -f "${CONF_DIR}/sip_profiles/external.xml" ]; then
  sed -i 's/name="sip-port" value="[^"]*"/name="sip-port" value="$${external_sip_port}"/' \
    "${CONF_DIR}/sip_profiles/external.xml"
  sed -i 's/name="ext-sip-port" value="[^"]*"/name="ext-sip-port" value="$${external_sip_port}"/' \
    "${CONF_DIR}/sip_profiles/external.xml"
  sed -i 's/name="tls-sip-port" value="[^"]*"/name="tls-sip-port" value="$${external_tls_port}"/' \
    "${CONF_DIR}/sip_profiles/external.xml"
fi

if [ -f "${CONF_DIR}/sip_profiles/internal.xml" ]; then
  sed -i 's/name="sip-port" value="[^"]*"/name="sip-port" value="$${internal_sip_port}"/' \
    "${CONF_DIR}/sip_profiles/internal.xml"
  sed -i 's/name="ext-sip-port" value="[^"]*"/name="ext-sip-port" value="$${internal_sip_port}"/' \
    "${CONF_DIR}/sip_profiles/internal.xml"
  sed -i 's/name="tls-sip-port" value="[^"]*"/name="tls-sip-port" value="$${internal_tls_port}"/' \
    "${CONF_DIR}/sip_profiles/internal.xml"
fi

echo "Updated ${CONF_DIR}: external UDP/TCP 5070, TLS 5071; internal 5060/5061"

if docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  ESL_PASSWORD="$(grep 'name="password"' "${CONF_DIR}/autoload_configs/event_socket.conf.xml" \
    | sed -n 's/.*value="\([^"]*\)".*/\1/p' | head -1 || true)"
  FS_CLI=(docker exec "${CONTAINER}" fs_cli)
  [ -n "${ESL_PASSWORD}" ] && FS_CLI+=( -p "${ESL_PASSWORD}" )
  "${FS_CLI[@]}" -x "reloadxml"
  "${FS_CLI[@]}" -x "sofia profile external restart"
  "${FS_CLI[@]}" -x "sofia profile internal restart"
  sleep 2
  "${FS_CLI[@]}" -x "sofia status"
fi
