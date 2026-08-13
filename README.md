# adguard-bind9 v2

A small, hardened DNS stack for a Debian Docker host:

```text
LAN / VLAN clients
       |
       | TCP+UDP 53
       v
+------------------+
|   AdGuard Home   |  filtering, policies, query log
|   172.30.0.4     |
+---------+--------+
          |
          | plain DNS, private Docker network
          v
+------------------+
|      BIND 9      |  recursive resolver + cache + DNSSEC validation
|   172.30.0.3     |
+---------+--------+
          |
          | direct recursive DNS
          v
     DNS root / TLD / authoritative servers
```

BIND has **no port published on the Docker host**.  Only AdGuard can reach it.
AdGuard is the only DNS service exposed to trusted LAN/VLAN clients.

## Main changes compared with v1

- AdGuard Home pinned to a stable release instead of an implicit `latest`.
- Canonical BIND 9.20 stable track instead of the deprecated `latest` track.
- No `BIND9_USER=root`; the image's safer default user handling is retained.
- DNSSEC validation enabled in BIND.
- BIND recursion/cache restricted to AdGuard and localhost.
- BIND no longer exposes host port 553.
- `/etc/bind` is no longer hidden by a broad bind mount.
- BIND uses its compiled-in root hints; the project ships its own minimal localhost zones, so there is no stale `db.root` to maintain and no dependency on distribution-specific `db.*` files.
- Removed the unused repository copy of `db.root` and the broken `example.com` zone.
- AdGuard `conf` and `work` storage are separated.
- Only plain DNS and the web/setup interfaces are published by default.
- Docker log rotation, memory guards and PID limits are configured.
- BIND uses its Canonical/Pebble health check and AdGuard waits for BIND health.
- Preflight, validation, DNS smoke-test, backup, update and v1 migration scripts.
- Optional `home.arpa` forward/reverse zone examples.
- CI validates Compose, BIND configuration and shell syntax.

## 1. Requirements

Designed for Debian 13 with Docker Engine and Docker Compose v2.

Useful host packages:

```bash
sudo apt update
sudo apt install -y ca-certificates curl dnsutils
```

Do **not** blindly uninstall DHCP packages.  The only networking requirement is
that the Debian host has a stable IP address and that port 53 is available.

Check port 53:

```bash
sudo ss -lntup | grep ':53'
```

If something already owns port 53, identify and deliberately reconfigure it
before starting this stack.

## 2. Configure the deployment

```bash
cp .env.example .env
nano .env
```

At minimum, set:

```dotenv
DNS_BIND_IP=192.168.1.10
WEB_BIND_IP=192.168.1.10
```

`DNS_BIND_IP` is the address that clients will use as their DNS server.
`WEB_BIND_IP` may be the same address or a dedicated management address.

The Docker-only resolver addresses are intentionally fixed:

```text
BIND     172.30.0.3
AdGuard  172.30.0.4
```

If `172.30.0.0/24` overlaps another local/Docker network, change the subnet and
both static addresses in `compose.yaml`, then also update the AdGuard address in
`config/bind9/named.conf.options`.

## 3. Preflight

```bash
./scripts/preflight.sh
```

Fix any reported hard failure before continuing.  Warnings about IPs or port 53
should be investigated rather than ignored.

## 4. First start

```bash
docker compose pull
docker compose up -d
```

Inspect:

```bash
docker compose ps
docker compose logs --tail=100 bind9
docker compose logs --tail=100 adguardhome
```

The BIND container is expected to become healthy before AdGuard is started.

## 5. Fresh AdGuard setup

Open:

```text
http://WEB_BIND_IP:3000/
```

During the wizard:

1. Keep the DNS server on port `53`.
2. Configure the production web interface on container port `80`.
3. Create a strong administrator account.
4. Finish the wizard, then use `http://WEB_BIND_IP/` (or the host-side
   `ADGUARD_WEB_PORT` chosen in `.env`).

In **Settings -> DNS settings** set:

```text
Upstream DNS servers:
172.30.0.3:53
```

Recommended for this architecture:

```text
Fallback DNS servers:   empty
Bootstrap DNS servers:  empty for this numeric upstream
```

The goal is to ensure normal DNS resolution follows only:

```text
client -> AdGuard -> BIND -> authoritative DNS hierarchy
```

Do not add Google/Cloudflare/Quad9 as a fallback if your goal is to keep BIND as
your recursive resolver.

## 6. Validate end-to-end

```bash
./scripts/test-dns.sh
```

The script verifies normal DNS resolution through AdGuard and performs a DNSSEC
negative test using `dnssec-failed.org`.  A `SERVFAIL` on that deliberately
broken DNSSEC domain is expected.

You can also test manually:

```bash
dig @192.168.1.10 example.org A
dig @192.168.1.10 dnssec-failed.org A
```

Replace `192.168.1.10` with `DNS_BIND_IP`.

## 7. Firewall policy

At the network/firewall layer, the intended policy is:

```text
trusted LAN/VLANs -> DNS_BIND_IP TCP/UDP 53    ALLOW
admin network     -> WEB_BIND_IP web port      ALLOW
WAN/untrusted     -> DNS and admin UI          DENY
```

BIND itself has no published host port, so it should never be directly
reachable from LAN or WAN.

If you route several VLANs through VyOS, allow TCP **and** UDP 53 from only the
VLANs that should use this resolver.

## 8. Operational commands

Status:

```bash
docker compose ps
```

Logs:

```bash
docker compose logs -f --tail=100 adguardhome
docker compose logs -f --tail=100 bind9
```

Restart:

```bash
docker compose restart
```

Validate configuration before a restart:

```bash
./scripts/validate.sh
```

## 9. Backups

Configuration-only backup, no DNS interruption:

```bash
./scripts/backup.sh config
```

Full AdGuard backup (briefly stops only AdGuard for consistency):

```bash
./scripts/backup.sh full
```

Archives are written under `backups/` with permissions `0600`.

The BIND recursive cache is stored in a Docker named volume and is intentionally
not treated as important backup data.  It can be rebuilt from DNS sources.

## 10. Updating

Image choices live in `.env`:

```dotenv
ADGUARD_IMAGE=adguard/adguardhome:v0.107.78
BIND_IMAGE=ubuntu/bind9:9.20-26.04_stable
```

For a new AdGuard stable release, edit `ADGUARD_IMAGE` deliberately.  The BIND
track follows Canonical's supported 9.20/26.04 stable channel.

Then:

```bash
./scripts/update.sh
./scripts/test-dns.sh
```

The update helper makes a configuration backup, runs preflight checks, pulls the
declared images, validates BIND, and recreates the stack.

## 11. Migrating from v1

**First make a copy/backup of the old project.**  Do not reuse the same directory
in-place for the first migration attempt.

Stop the old v1 stack so it releases host port 53:

```bash
cd /path/to/old/adguard-bind9-main
docker compose down
```

From the v2 directory:

```bash
./scripts/migrate-v1.sh /path/to/old/adguard-bind9-main
```

The migration script understands the v1 layout where the same host directory was
mounted as both AdGuard `conf` and `work`.  It copies:

```text
old data/adguard/AdGuardHome.yaml -> new data/adguard/conf/AdGuardHome.yaml
old data/adguard/data/            -> new data/adguard/work/data/
```

It intentionally does **not** copy the old BIND configuration because the point
of v2 is to replace that configuration with the corrected resolver setup.

Then edit `.env`, run preflight, start v2 and test it.  Keep the old project until
you have confirmed DNS, filtering and the admin UI all work.

Because v1 normally configured the AdGuard web interface on internal port 80,
the v2 production mapping retains container port 80 and is migration-friendly.

## 12. Optional internal DNS with `home.arpa`

RFC 8375 reserves `home.arpa` for local home-network names.  Examples are in:

```text
examples/bind9/home.arpa/
```

To use them:

1. Adapt hostnames/IPs and reverse subnet.
2. Copy the zone databases into `config/bind9/zones/`.
3. Add the zone declarations to `config/bind9/named.conf.local`.
4. Increment the SOA serial every time a zone changes.
5. Run `./scripts/validate.sh`.
6. Restart BIND: `docker compose restart bind9`.

Example names could become:

```text
router.home.arpa
esxi.home.arpa
idrac.home.arpa
plex.home.arpa
```

## 13. Why there is no AdGuard container healthcheck

The upstream AdGuard project removed its Docker healthcheck because generic
health checks produced edge cases, excess I/O and problematic restart loops in
some deployments.  This v2 therefore uses:

- Canonical's native Pebble health for BIND, so startup order is reliable;
- an explicit end-to-end `scripts/test-dns.sh` for the complete DNS path;
- Docker's normal `restart: unless-stopped` policy for process failures.

This avoids pretending that a generic HTTP probe proves the DNS/filtering path is
healthy.

## 14. Security notes

- Never publish BIND's port 53 directly unless you have a specific reason.
- Do not expose the AdGuard admin UI to the Internet.
- Do not configure an unrestricted WAN-facing recursive resolver.
- Keep AdGuard and BIND images updated after reviewing stable release notes.
- Back up `data/adguard/conf/AdGuardHome.yaml`; it contains your operational
  configuration and administrator credentials (hashed, but still sensitive).
- Keep `.env`, runtime data, local zone files and backups out of public Git repos.
- The Compose logging driver is `local` with rotation to prevent unbounded
  `json-file` growth.

## Project layout

```text
.
├── compose.yaml
├── .env.example
├── .gitignore
├── config/
│   └── bind9/
│       ├── named.conf
│       ├── named.conf.options
│       ├── named.conf.local
│       ├── named.conf.local-zones
│       └── zones/
│           └── system/
├── data/
│   └── adguard/
│       ├── conf/
│       └── work/
├── examples/
│   └── bind9/home.arpa/
├── scripts/
│   ├── preflight.sh
│   ├── validate.sh
│   ├── test-dns.sh
│   ├── backup.sh
│   ├── update.sh
│   └── migrate-v1.sh
└── .github/workflows/validate.yml
```

## References

- AdGuard Home Docker: https://github.com/AdguardTeam/AdGuardHome/wiki/Docker
- AdGuard Home releases: https://github.com/AdguardTeam/AdGuardHome/releases
- Canonical BIND image: https://hub.docker.com/r/ubuntu/bind9
- BIND 9 ARM/reference docs: https://bind9.readthedocs.io/
- Docker Compose startup order: https://docs.docker.com/compose/how-tos/startup-order/
- Docker local logging driver: https://docs.docker.com/engine/logging/drivers/local/
