#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLD_ROOT="${1:-}"

if [[ -z "$OLD_ROOT" ]]; then
    echo "Usage: $0 /path/to/old/adguard-bind9-main" >&2
    exit 2
fi

OLD_ADGUARD="$OLD_ROOT/data/adguard"
NEW_CONF="$ROOT/data/adguard/conf"
NEW_WORK="$ROOT/data/adguard/work"

[[ -d "$OLD_ADGUARD" ]] || { echo "Not found: $OLD_ADGUARD" >&2; exit 1; }
[[ -f "$OLD_ADGUARD/AdGuardHome.yaml" ]] || {
    echo "No AdGuardHome.yaml found in $OLD_ADGUARD; nothing safe to migrate automatically." >&2
    exit 1
}

if [[ -f "$NEW_CONF/AdGuardHome.yaml" ]]; then
    echo "Refusing to overwrite existing $NEW_CONF/AdGuardHome.yaml" >&2
    exit 1
fi

mkdir -p "$NEW_CONF" "$NEW_WORK"
cp -a "$OLD_ADGUARD/AdGuardHome.yaml" "$NEW_CONF/AdGuardHome.yaml"

if [[ -d "$OLD_ADGUARD/data" ]]; then
    rm -rf "$NEW_WORK/data"
    cp -a "$OLD_ADGUARD/data" "$NEW_WORK/data"
fi

cat <<MSG
Migration copy complete.

Copied:
  AdGuardHome.yaml -> data/adguard/conf/
  runtime data     -> data/adguard/work/data/ (when present)

The old BIND configuration was intentionally NOT copied: v2 replaces it with
its hardened resolver configuration. Review .env, then run:
  ./scripts/preflight.sh
  docker compose up -d
  ./scripts/test-dns.sh

Do not delete the old project until the v2 has been tested.
MSG
