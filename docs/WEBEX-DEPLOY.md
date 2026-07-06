# Webex Calling trunk — standalone FreeSWITCH deploy

Deploy a **dedicated** FreeSWITCH instance for Webex Calling registration trunk testing
(fax, inbound/outbound voice). This is separate from the recording portal stack on
`hyetech@172.25.100.83`.

## Dev host

| Item | Value |
|------|-------|
| SSH | `root@srv1608468.hstgr.cloud` |
| Public IPv4 | `2.24.221.60` |
| Remote path | `/opt/ccc-freeswitch-webex` |
| Container | `freeswitch` (host network) |

### Legacy `ccc-fax` native FreeSWITCH

This host previously ran a **systemd-managed** native FreeSWITCH (`freeswitch.service`
from `/opt/ccc-fax`). It also binds host SIP ports and conflicts with the Docker
container. For the Webex dev instance, the legacy service was **stopped and disabled**:

```bash
systemctl stop freeswitch && systemctl disable freeswitch
docker restart freeswitch
```

To restore the old `ccc-fax` stack, stop the Docker container and re-enable the service.

## Deploy from workspace root

```bash
cd /path/to/Projects   # workspace root (parent of ccc-freeswitch-docker)
make deploy-webex
# or
./deploy/deploy-freeswitch.sh
```

The deploy script rsyncs the repo, sets `external_sip_ip` / `external_rtp_ip` / `local_ip_v4`
to the host public IP, and runs `docker compose up -d --build`.

## Control Hub credentials (required before registration works)

Edit on the server:

```bash
ssh root@srv1608468.hstgr.cloud
nano /opt/ccc-freeswitch-webex/runtime/config/vars.xml
```

Replace the six `webex_*` placeholders (from **Control Hub → Calling → Call Routing → Trunks →
Add Trunk → Registration based**):

| var | Control Hub field |
|-----|-------------------|
| `webex_registrar` | Registrar FQDN |
| `webex_outbound_proxy` | Outbound proxy FQDN (DNS SRV → port 8934) |
| `webex_line_port` | Line/Port user part (before `@`) |
| `webex_username` | Trunk username (digest auth) |
| `webex_password` | Trunk password |
| `webex_otg` | Outbound trunk group tag |

Then reload:

```bash
cd /opt/ccc-freeswitch-webex
docker exec freeswitch fs_cli -x "reloadxml"
docker exec freeswitch fs_cli -x "sofia profile external restart"
docker exec freeswitch fs_cli -x "sofia status gateway webex"
```

**Registration OK** shows `State REGED`. Until credentials are pasted, expect `FAIL_WAIT` or auth errors.

## Ports / firewall

FreeSWITCH uses **host networking**. Ensure these are open on the cloud firewall:

| Port | Protocol | Purpose |
|------|----------|---------|
| 5070 | UDP/TCP | External SIP (non-default to avoid clashes) |
| 5071 | TCP | External SIP TLS |
| 16384-32768 | UDP | RTP/SRTP |
| 8021 | TCP | ESL (localhost only — do not expose publicly) |

Outbound: TLS to Webex on port **8934** (via DNS SRV on `webex_outbound_proxy`).

## Verify / debug

```bash
# Container health
docker ps --filter name=freeswitch
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "status"

# Gateway registration
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "sofia status gateway webex"

# SIP trace (temporary)
docker exec freeswitch fs_cli -H 127.0.0.1 -P 8021 -p ChangeMe-ESL-Password -x "sofia profile external siptrace on"

# Logs
docker logs freeswitch --tail 100
tail -f /opt/ccc-freeswitch-webex/runtime/logs/freeswitch.log
```

### Inbound test

With registration up, dial the Line/Port number from Webex. The default dialplan transfers
to extension `9191` (health-check tone).

### Outbound test

```bash
docker exec freeswitch fs_cli -x "originate {origination_caller_id_number=+1XXXXXXXXXX}sofia/gateway/webex/+1YYYYYYYYYY &echo"
```

### Fax (Phase 2)

Inbound fax example is commented in `config/dialplan/default.xml`. Uncomment `inbound_fax`,
sync config, and test T.38 after voice trunk is stable.

## Update after local changes

```bash
# From workspace root, after committing ccc-freeswitch-docker changes:
make deploy-webex
```

## What's left

- [ ] Paste Control Hub `webex_*` values into server `vars.xml`
- [ ] Confirm `sofia status gateway webex` → `REGED`
- [ ] Place test inbound/outbound calls
- [ ] Enable and test T.38 fax dialplan
