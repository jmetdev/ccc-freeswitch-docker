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
