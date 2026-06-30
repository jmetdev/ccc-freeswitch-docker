#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-ccc-freeswitch-docker:dev}"
CONTAINER="freeswitch-smoke-test-$$"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${ROOT}/runtime"
ESL_PASSWORD="${ESL_PASSWORD:-ChangeMe-ESL-Password}"

# Prefer native arm64 on Apple Silicon, amd64 elsewhere
ARCH="$(uname -m)"
if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
  PLATFORM="${SMOKE_PLATFORM:-linux/arm64}"
  IMAGE="${SMOKE_IMAGE:-ccc-freeswitch-docker:dev-arm64}"
else
  PLATFORM="${SMOKE_PLATFORM:-linux/amd64}"
fi

mkdir -p "${RUNTIME}/config" "${RUNTIME}/logs" "${RUNTIME}/recordings" "${RUNTIME}/fax"

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Starting container ${IMAGE} (${PLATFORM})"
docker run -d --name "${CONTAINER}" --platform "${PLATFORM}" \
  -p 18021:8021 \
  --cap-add SYS_NICE \
  -v "${RUNTIME}/config:/etc/freeswitch" \
  -v "${RUNTIME}/logs:/var/log/freeswitch" \
  -v "${RUNTIME}/recordings:/var/lib/freeswitch/recordings" \
  -v "${RUNTIME}/fax:/var/spool/fax" \
  "${IMAGE}" >/dev/null

echo "==> Waiting for FreeSWITCH to start"
for _ in $(seq 1 30); do
  if docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x status 2>/dev/null | grep -q '^UP'; then
    break
  fi
  sleep 2
done

echo "==> Status"
docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x status

echo "==> Module checks"
for mod in mod_event_socket mod_spandsp mod_sofia mod_sndfile; do
  docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "module_exists ${mod}" | grep -q true
  echo "  ${mod}: OK"
done

echo "==> mod_signalwire must be absent"
if docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "module_exists mod_signalwire" | grep -q true; then
  echo "ERROR: mod_signalwire is loaded" >&2
  exit 1
fi
echo "  mod_signalwire: absent (OK)"

echo "==> ESL Python check"
docker exec -e ESL_PASSWORD="${ESL_PASSWORD}" "${CONTAINER}" python3 -c "
import os, socket
password = os.environ['ESL_PASSWORD']
s = socket.create_connection(('127.0.0.1', 8021), timeout=5)
assert 'auth/request' in s.recv(4096).decode()
s.send(f'auth {password}\n\n'.encode())
assert '+OK accepted' in s.recv(4096).decode()
s.send(b'api status\n\n')
assert 'UP' in s.recv(8192).decode()
s.close()
print('ESL auth + api status: OK')
"

echo "==> record_session capability"
docker exec "${CONTAINER}" fs_cli -H 127.0.0.1 -P 8021 -p "${ESL_PASSWORD}" -x "show application record_session" | grep -q record_session
echo "  record_session application: OK"

echo
echo "All smoke tests passed."
