# Wazuh Agent + Suricata 8.0.2 Container

Runs a **Wazuh agent** and **Suricata 8.0.2 IDS** side-by-side in a single Docker container using [s6-overlay](https://github.com/just-containers/s6-overlay) v3.1.6.2 for process supervision.

## Prerequisites

- Docker + Compose plugin (or `docker-compose`)
- `sslagent.key` and `sslagent.cert` placed in `volumes/wazuh-agent/` (SSL pair for Wazuh agent enrollment)
- A Wazuh manager reachable on your network

## Quick Start

```bash
# 1. Place your SSL keypair
cp /path/to/sslagent.key volumes/wazuh-agent/
cp /path/to/sslagent.cert volumes/wazuh-agent/

# 2. Set your Wazuh manager IP in compose.yml (WAZUH_MANAGER)

# 3. Build and start
docker compose up -d

# 4. Check that everything is running
docker compose exec wazuh-agent cat /var/ossec/var/run/wazuh-agentd.state | grep status  # agent connected?
docker compose exec wazuh-agent wc -l /opt/wazuh/suricata/var/log/suricata/fast.log  # alerts?
```

## Configuration

| Variable | Where | Purpose |
|---|---|---|
| `WAZUH_MANAGER` | `compose.yml` environment | Wazuh manager IP or hostname |
| `volumes/wazuh-agent/ossec.conf` | Bind-mounted | Agent config with `<address>` placeholder |
| `volumes/suricata/suricata.yaml` | Copied into image at build | Suricata engine config |
| `volumes/suricata/nmap-detection.rules` | Bind-mounted | Custom rules for detecting nmap scans |

## Project Structure

```
.
├── Dockerfile                      # Builds the image
├── compose.yml                     # Runtime config (env, volumes, ports, caps)
├── s6-rc.d/
│   ├── .config-init                # Shared init script sourced by both services
│   ├── wazuh-agent/                # s6 longrun service
│   │   ├── type                    # "longrun"
│   │   ├── run                     # Starts wazuh-control, then sleep infinity
│   │   └── finish                  # Stops wazuh-control
│   ├── suricata/                   # s6 longrun service
│   │   ├── type                    # "longrun"
│   │   ├── run                     # Starts suricata on default interface
│   │   └── finish                  # Cleans up pidfile
│   └── user/contents.d/            # Bundle of services to start
│       ├── wazuh-agent
│       └── suricata
└── volumes/
    ├── wazuh-agent/
    │   ├── ossec.conf              # Agent configuration template
    │   ├── sslagent.key            # SSL key (bind mount)
    │   └── sslagent.cert           # SSL cert (bind mount)
    └── suricata/
        ├── suricata.yaml           # Suricata configuration
        └── nmap-detection.rules    # Custom nmap scan detection rules from [vlaicu.io](https://vlaicu.io/posts/suricata-nmap-rules/)
```

## How It Works

### s6-overlay Supervision

Both processes run as **longrun** services under s6, meaning s6 keeps them alive and handles restart/logging. No separate oneshot is used for config-init — instead, both `run` scripts source `.config-init` at startup.

### Config Init (`.config-init`)

The shared init script:

1. **Imports container env vars** — s6-overlay v3 strips environment from PID1 but stores them as files in `/run/s6/container_environment/`. The script reads them back into shell variables.
2. **One-time setup with `mkdir` lock** — Substitutes `WAZUH_MANAGER` into `ossec.conf` and fixes ownership of SSL files, guarded by `mkdir` so it only runs once even when both services source it in parallel.

### Suricata

Suricata uses the [ADORSYS-GIS](https://github.com/ADORSYS-GIS/wazuh-plugins/releases) bundled build at `/opt/wazuh/suricata/bin/suricata`. `LD_LIBRARY_PATH` is set to `/opt/wazuh/suricata/lib` for its bundled shared libraries. It auto-detects the default network interface from the route table.

## Testing Nmap Detection

From any host on the same Docker network, run:

```bash
# SYN scan (will trigger nmap detection rules)
nmap -sS -p 1-500 -T5 <container-ip>

# XMAS scan
nmap -sX -T5 <container-ip>

# Check alerts
docker compose exec wazuh-agent tail -f /opt/wazuh/suricata/var/log/suricata/fast.log
```

The rules use threshold-based detection (e.g., 7 matching packets within 135 seconds) to reduce false positives.

## Notes

- The container requires `privileged: true` and `NET_ADMIN`/`NET_RAW` capabilities for Suricata to work properly.
- Default Docker bridge mode only lets Suricata inspect traffic routed *to* the container. For host traffic inspection, set `network_mode: host` in `compose.yml`. This breaks network isolation but lets Suricata see the host's physical interface.
- Wazuh agent is pinned to `4.14.3-1` (the highest version below 4.14.4 in the Wazuh 4.x repo).
- Suricata 8.0.2 .deb is downloaded from the ADORSYS-GIS GitHub release (bundled build with static libs), not from OISF PPA.
