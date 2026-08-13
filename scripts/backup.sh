#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-config}"
case "$MODE" in
    config|full) ;;
    *) echo "Usage: $0 [config|full]" >&2; exit 2 ;;
esac

mkdir -p backups
umask 077
STAMP="$(date +'%Y%m%d-%H%M%S')"
ARCHIVE="backups/adguard-bind9-${MODE}-${STAMP}.tar.gz"

restart_adguard=0
cleanup() {
    if [[ "$restart_adguard" -eq 1 ]]; then
        docker compose start adguardhome >/dev/null
    fi
}
trap cleanup EXIT

items=(compose.yaml .env.example config data/adguard/conf)
[[ -f .env ]] && items+=(.env)

if [[ "$MODE" == "full" ]]; then
    if docker compose ps --status running --services 2>/dev/null | grep -qx 'adguardhome'; then
        echo "Stopping AdGuard Home briefly for a consistent full backup..."
        docker compose stop adguardhome >/dev/null
        restart_adguard=1
    fi
    items+=(data/adguard/work)
fi

tar -czf "$ARCHIVE" "${items[@]}"
chmod 600 "$ARCHIVE"

echo "Backup created: $ARCHIVE"
if [[ "$MODE" == "config" ]]; then
    echo "Query statistics/runtime data were intentionally excluded. Use '$0 full' to include them."
fi
