# ccc-freeswitch-docker

FreeSWITCH Docker image (Debian Trixie)

Lean, multi-arch FreeSWITCH container for SIP trunking projects. Built from upstream source without `mod_signalwire`.

Based on [PatrickBaus/freeswitch-docker](https://github.com/PatrickBaus/freeswitch-docker), adapted for **Debian Trixie slim** with a curated module set.

## Features

- SIP trunks over **UDP, TCP, and TLS** (`mod_sofia`)
- Cloud registration trunks (e.g. Webex Calling) and on-prem trunks (e.g. CUCM)
- **SpanDSP** fax/T.38 (`mod_spandsp`)
- **ESL** for Python control (`mod_event_socket` + `--with-python3`)
- **WAV recording** via `record_session` (`mod_dptools` + `mod_sndfile`)
- **Multi-arch**: `linux/amd64` and `linux/arm64`
- No SignalWire token or `mod_signalwire`

## Quick Start

```bash
# Build locally (amd64)
make build-local

# Run with host networking (recommended for RTP)
mkdir -p runtime/{config,logs,recordings,fax}
docker compose up -d

# Check status
docker exec freeswitch fs_cli -x status
```

## Volumes

| Mount | Purpose |
|-------|---------|
| `/etc/freeswitch` | Configuration (seeded from `/etc/freeswitch.default` on first run) |
| `/var/log/freeswitch` | Logs |
| `/var/lib/freeswitch/recordings` | WAV recordings |
| `/var/spool/fax` | Inbound/outbound fax spool |

## Networking

Use **`network_mode: host`** on Linux (default in `docker-compose.yml`). RTP uses UDP ports `16384-32768`, which is impractical to map in bridge mode.

**Docker Desktop (macOS/Windows):** host networking is not fully supported. For local development, publish ports instead (see `scripts/smoke-test.sh` for an example mapping `18021:8021`).

Add `cap_add: SYS_NICE` for realtime scheduling.

## ESL (Python)

Default ESL binds to `127.0.0.1:8021` with password `ChangeMe-ESL-Password` (change in `event_socket.conf.xml`). The image ships `/etc/fs_cli.conf` with matching credentials for `fs_cli`.

```python
# Example with greenswitch (pip install greenswitch)
from greenswitch import InboundESL
esl = InboundESL(host="127.0.0.1", port=8021, password="ChangeMe-ESL-Password")
esl.connect()
print(esl.send("api status"))
```

## Recording

```xml
<action application="set" data="RECORD_STEREO=true"/>
<action application="record_session" data="$${recordings_dir}/${uuid}.wav"/>
<action application="bridge" data="sofia/gateway/my_trunk/${destination_number}"/>
```

## SIP Gateways

See `config/sip_profiles/external/example_gateways.xml` for Webex and CUCM stubs.

### Webex Calling

- TLS 1.2+, SRTP `AES_CM_128_HMAC_SHA1_80`
- Public FQDN + certs in `/etc/freeswitch/certs`
- `register-transport=tls` on gateway

### CUCM

- UDP/TCP/TLS per deployment
- Codecs: `PCMU,PCMA,G729,OPUS` (adjust in `vars.xml`)

## Build Args

| Arg | Default |
|-----|---------|
| `FREESWITCH_VERSION` | `v1.11.1` |
| `SOFIA_VERSION` | `v1.13.17` |
| `SPANDSP_COMMIT` | pinned pre-API-break commit |

## Multi-Arch Build

```bash
make build PLATFORMS=linux/amd64,linux/arm64 IMAGE=ghcr.io/you/ccc-freeswitch-docker TAG=v1.11.1
```

CI publishes manifest lists via `.github/workflows/build.yml`.

## Modules Included

`mod_console`, `mod_logfile`, `mod_event_socket`, `mod_sofia`, `mod_loopback`, `mod_rtc`, `mod_dialplan_xml`, `mod_commands`, `mod_dptools`, `mod_expr`, `mod_hash`, `mod_spandsp`, `mod_sndfile`, `mod_tone_stream`, `mod_local_stream`, `mod_say_en`, `mod_opus`, `mod_amr`, `mod_g723_1`, `mod_g729`, `mod_b64`

## G.729 Note

`mod_g729` uses bcg729. Review patent/licensing requirements for your jurisdiction.

## Upgrading SpanDSP / FreeSWITCH

SpanDSP is pinned to a commit compatible with FreeSWITCH 1.10.x. When bumping FreeSWITCH versions, re-validate the SpanDSP pin in the Dockerfile.

## Call Recording Portal (companion repo)

This image is generic and carries **no** portal-specific code. The CUCM BIB call
recording portal — and the FreeSWITCH integration that feeds it (BIB dialplan,
ACL, and hangup hook scripts) — lives in a separate repo:
[`ccc-recording-portal`](https://github.com/jmetdev/ccc-recording-portal).

When you deploy the portal alongside this container, its `freeswitch/` folder is
layered on top: the dialplan/ACL are copied into `runtime/config/`, and the hook
scripts are mounted at `/usr/local/sbin` via an additive compose override that
also supplies the `PORTAL_API_URL` / `INGEST_TOKEN` env the hooks need.

For deploying both repos on one host, see
[docs/DEPLOY-SPLIT-REPOS.md](docs/DEPLOY-SPLIT-REPOS.md) and the portal's
`freeswitch/README.md`.
