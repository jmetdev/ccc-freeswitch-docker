#!/bin/sh
set -eu

DEFAULT_CONFIG="/etc/freeswitch.default"
LIVE_CONFIG="/etc/freeswitch"

if [ ! -f "${LIVE_CONFIG}/freeswitch.xml" ]; then
  echo "Seeding ${LIVE_CONFIG} from ${DEFAULT_CONFIG}..."
  cp -a "${DEFAULT_CONFIG}/." "${LIVE_CONFIG}/"
fi

if [ -f "${DEFAULT_CONFIG}/fs_cli.conf" ]; then
  cp -f "${DEFAULT_CONFIG}/fs_cli.conf" /etc/fs_cli.conf
fi

# TLS material for the sofia profiles (Webex Calling requires TLS 1.2).
# agent.pem: self-signed identity cert; registration-based trunks do not
# require a CA-signed client certificate.
# cafile.pem: system CA bundle so tls-verify-policy=out can validate the
# Webex server certificate.
CERTS_DIR="${LIVE_CONFIG}/certs"
mkdir -p "${CERTS_DIR}"
if [ ! -f "${CERTS_DIR}/agent.pem" ] && command -v openssl >/dev/null 2>&1; then
  echo "Generating self-signed TLS agent certificate..."
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -subj "/CN=freeswitch" \
    -keyout "${CERTS_DIR}/agent.key" -out "${CERTS_DIR}/agent.crt"
  cat "${CERTS_DIR}/agent.crt" "${CERTS_DIR}/agent.key" > "${CERTS_DIR}/agent.pem"
  rm -f "${CERTS_DIR}/agent.crt" "${CERTS_DIR}/agent.key"
  chmod 600 "${CERTS_DIR}/agent.pem"
fi
if [ ! -f "${CERTS_DIR}/cafile.pem" ] && [ -f /etc/ssl/certs/ca-certificates.crt ]; then
  cp /etc/ssl/certs/ca-certificates.crt "${CERTS_DIR}/cafile.pem"
fi

mkdir -p \
  "${LIVE_CONFIG}" \
  /var/log/freeswitch \
  /var/lib/freeswitch/recordings \
  /var/spool/fax \
  /run/freeswitch

chown -R freeswitch:freeswitch \
  /var/log/freeswitch \
  /var/lib/freeswitch \
  /var/spool/fax \
  /run/freeswitch \
  2>/dev/null || true

exec "$@"
