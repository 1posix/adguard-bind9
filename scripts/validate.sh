#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f .env ]] || { echo "Missing .env (copy .env.example first)." >&2; exit 1; }
# shellcheck disable=SC1091
set -a
source ./.env
set +a

BIND_IMAGE="${BIND_IMAGE:-ubuntu/bind9:9.20-26.04_stable}"

echo "[1/3] Docker Compose syntax"
docker compose config --quiet

echo "[2/3] BIND configuration"
if docker compose ps --status running --services 2>/dev/null | grep -qx 'bind9'; then
    docker compose exec -T bind9 named-checkconf -z /etc/bind/named.conf
else
    docker run --rm --network none \
        -v "$ROOT/config/bind9/named.conf:/etc/bind/named.conf:ro" \
        -v "$ROOT/config/bind9/named.conf.options:/etc/bind/named.conf.options:ro" \
        -v "$ROOT/config/bind9/named.conf.local:/etc/bind/named.conf.local:ro" \
        -v "$ROOT/config/bind9/named.conf.local-zones:/etc/bind/named.conf.local-zones:ro" \
        -v "$ROOT/config/bind9/zones:/etc/bind/zones:ro" \
        --entrypoint named-checkconf \
        "$BIND_IMAGE" -z /etc/bind/named.conf
fi

echo "[3/3] Shell syntax"
for script in scripts/*.sh; do
    bash -n "$script"
done

echo "Validation successful."
