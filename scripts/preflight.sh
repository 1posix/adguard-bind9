#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ok()   { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "Docker is not installed."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is not available (docker compose)."
ok "Docker and Docker Compose are available."

[[ -f .env ]] || fail "Missing .env. Run: cp .env.example .env, then edit the IP addresses."

# shellcheck disable=SC1091
set -a
source ./.env
set +a

[[ -n "${DNS_BIND_IP:-}" ]] || fail "DNS_BIND_IP is empty in .env."
[[ -n "${WEB_BIND_IP:-}" ]] || fail "WEB_BIND_IP is empty in .env."

if command -v ip >/dev/null 2>&1; then
    ip -4 addr show | grep -Fq " ${DNS_BIND_IP}/" \
        || warn "DNS_BIND_IP=${DNS_BIND_IP} was not found on a local IPv4 interface."
    ip -4 addr show | grep -Fq " ${WEB_BIND_IP}/" \
        || warn "WEB_BIND_IP=${WEB_BIND_IP} was not found on a local IPv4 interface."
fi

if command -v ss >/dev/null 2>&1; then
    if ! docker ps --format '{{.Names}}' | grep -qx 'adguardhome'; then
        if ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq '(^|:)53$'; then
            warn "Something is already listening on port 53. Inspect with: sudo ss -lntup | grep ':53'."
        else
            ok "Port 53 does not appear to be occupied by another listening service."
        fi
    fi
fi

docker compose config --quiet
ok "compose.yaml is valid."

printf '\nPreflight complete.\n'
