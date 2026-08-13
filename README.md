# adguard-bind9

A simple self-hosted DNS stack combining **AdGuard Home** with a private **BIND 9 recursive resolver**.

AdGuard handles filtering and client policies. BIND resolves domains directly through the DNS hierarchy, provides caching, and validates DNSSEC — without requiring a public recursive provider such as Google, Cloudflare or Quad9.

## Architecture

```text
LAN / VLAN clients
        |
        | TCP + UDP 53
        v
+----------------------+ 
|     AdGuard Home     |
|      172.30.0.4      |
|                      |
| filtering / policies |
+----------+-----------+
           |
           | private Docker network
           v
+----------------------+
|        BIND 9        |
|      172.30.0.3      |
|                      |
| recursion / cache    |
| DNSSEC validation    |
+----------+-----------+
           |
           v
 Root -> TLD -> Authoritative DNS
```

**BIND is never published on the Docker host.** Only AdGuard can query it directly.

| Component | Role |
|---|---|
| **AdGuard Home** | Filtering, client policies, query logs, DNS frontend |
| **BIND 9** | Recursive resolution, cache, DNSSEC validation |
| **Docker network** | Private communication between AdGuard and BIND |

## Highlights

- AdGuard Home DNS filtering
- Private BIND 9 recursive resolver
- DNSSEC validation enabled
- No public recursive DNS upstream required
- BIND isolated from the host network
- Restricted recursion/cache access
- Persistent AdGuard configuration
- Docker log rotation and resource limits
- BIND health check and startup ordering
- Validation, backup, update and migration scripts
- Optional `home.arpa` local DNS examples
- GitHub Actions configuration validation

## Requirements

- Linux Distro
- Docker Compose v2
- A stable IP address
- TCP/UDP port `53` available

Useful tools:

```bash
sudo apt update
sudo apt install -y ca-certificates curl dnsutils
```

### Networking step from v1

After configuring a fixed IP address, the original v1 setup removed the DHCP client and rebooted:

```bash
sudo apt remove isc-dhcp-client -y
sudo reboot
```

Make sure the server already has its intended static network configuration before running this step.

Check whether port 53 is already in use:

```bash
sudo ss -lntup | grep ':53'
```

## Quick start

Clone the repository:

```bash
git clone https://github.com/1posix/adguard-bind9.git
cd adguard-bind9
```

Create your local configuration:

```bash
cp .env.example .env
nano .env
```

Set at least:

```dotenv
DNS_BIND_IP=192.168.1.10
WEB_BIND_IP=192.168.1.10
```

Replace `192.168.1.10` with the IP address of your Debian host.

The internal Docker addresses are fixed by default:

```text
BIND     172.30.0.3
AdGuard  172.30.0.4
```

> If `172.30.0.0/24` conflicts with an existing network, adapt the subnet and static addresses in `compose.yaml` and the AdGuard ACL in `config/bind9/named.conf.options`.

Run the preflight checks:

```bash
./scripts/preflight.sh
```

Start the stack:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

BIND should become `healthy` before AdGuard starts.

## Configure AdGuard Home

For a fresh installation, open:

```text
http://SERVER_IP:3000/
```

Complete the setup wizard and create your administrator account.

Then open the normal interface:

```text
http://SERVER_IP/
```

Go to **Settings -> DNS settings** and configure:

```text
Upstream DNS servers:
172.30.0.3:53

Fallback DNS servers:
(empty)

Bootstrap DNS servers:
(empty)
```

The expected resolution path is:

```text
Client -> AdGuard -> BIND -> Root/TLD/Authoritative DNS
```

## Validate the stack

Run the end-to-end test:

```bash
./scripts/test-dns.sh
```

It verifies normal DNS resolution through AdGuard and performs a DNSSEC negative test with `dnssec-failed.org`.

A `SERVFAIL` response for that deliberately broken DNSSEC domain is expected.

Manual tests:

```bash
dig @192.168.1.10 example.org A
dig @192.168.1.10 dnssec-failed.org A
```

Replace `192.168.1.10` with your `DNS_BIND_IP`.

<details>
<summary><strong>Migrating from v1</strong></summary>

<br>

Keep a backup of the old project before starting.

Stop the old stack:

```bash
cd /path/to/old/adguard-bind9
docker compose down
```

From the v2 directory:

```bash
./scripts/migrate-v1.sh /path/to/old/adguard-bind9
```

The migration helper keeps the existing AdGuard configuration and runtime data while replacing the old BIND configuration with the v2 resolver setup.

Then:

```bash
./scripts/preflight.sh
docker compose up -d
./scripts/test-dns.sh
```

Keep the old project until DNS resolution, filtering and the AdGuard interface have been verified.

</details>

<details>
<summary><strong>Common operations</strong></summary>

<br>

Status:

```bash
docker compose ps
```

Logs:

```bash
docker compose logs -f --tail=100 adguardhome
docker compose logs -f --tail=100 bind9
```

Validate configuration:

```bash
./scripts/validate.sh
```

Restart:

```bash
docker compose restart
```

Stop / start:

```bash
docker compose down
docker compose up -d
```

</details>

<details>
<summary><strong>Backups and updates</strong></summary>

<br>

Configuration backup:

```bash
./scripts/backup.sh config
```

Full AdGuard backup:

```bash
./scripts/backup.sh full
```

Backups are stored in `backups/`.

Image versions are configured in `.env`, for example:

```dotenv
ADGUARD_IMAGE=adguard/adguardhome:v0.107.78
BIND_IMAGE=ubuntu/bind9:9.20-26.04_stable
```

After changing an image version:

```bash
./scripts/update.sh
./scripts/test-dns.sh
```

Prefer deliberate version updates over unpinned `latest` images.

</details>

## Local DNS

BIND can also provide optional local DNS using the RFC 8375 reserved domain `home.arpa`.

A complete generic example is available in:

```text
examples/bind9/home.arpa/
├── db.home.arpa.example
├── db.192.168.1.example
└── named.conf.local.example
```

The example contains both:

- a **forward zone**: hostname → IP address
- a **reverse zone**: IP address → hostname

Generic records can be adapted to any home, lab or small-office network:

```text
gateway.home.arpa
dns.home.arpa
server.home.arpa
nas.home.arpa
printer.home.arpa
client.home.arpa
```

For example:

```text
server.home.arpa  -> 192.168.1.10
192.168.1.10      -> server.home.arpa
```

Copy and adapt the example files to your own subnet, hostnames and addresses, then declare the zones in `config/bind9/named.conf.local`.

Validate the configuration before restarting BIND:

```bash
./scripts/validate.sh
docker compose restart bind9
```

Private production zones should stay out of the public repository.

## Security

- BIND is not published directly on the Docker host.
- BIND recursion/cache access is restricted to AdGuard and localhost.
- Do not expose the AdGuard administration interface to the Internet.
- Only allow DNS access from trusted LAN/VLAN networks.
- Keep `.env`, AdGuard runtime data, backups and private DNS zones out of Git.
- Keep AdGuard Home and BIND updated after reviewing stable releases.

## Project structure

```text
.
├── compose.yaml
├── .env.example
├── .gitignore
├── VERSION
├── CHANGELOG.md
├── config/bind9/       # BIND configuration
├── data/adguard/       # Persistent AdGuard data
├── examples/bind9/     # Optional local DNS examples
├── scripts/            # Validation / backup / update tools
└── .github/workflows/  # CI validation
```

## References

- [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)
- [AdGuard Home Docker documentation](https://github.com/AdguardTeam/AdGuardHome/wiki/Docker)
- [AdGuard Home releases](https://github.com/AdguardTeam/AdGuardHome/releases)
- [BIND 9 documentation](https://bind9.readthedocs.io/)
- [Canonical BIND 9 Docker image](https://hub.docker.com/r/ubuntu/bind9)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [RFC 8375 - `home.arpa`](https://datatracker.ietf.org/doc/html/rfc8375)

## Upstream

This repository is based on the original project:

- [s4dic/adguard-bind9](https://github.com/s4dic/adguard-bind9)

Version 2 keeps the original goal — running AdGuard Home and BIND together — while redesigning the stack for stronger isolation, validation, DNSSEC and maintainability.
