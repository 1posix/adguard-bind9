#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f .env ]] || { echo "Missing .env." >&2; exit 1; }

./scripts/backup.sh config
./scripts/preflight.sh

echo "Pulling the image versions/tracks declared in .env..."
docker compose pull

./scripts/validate.sh

echo "Applying the update..."
docker compose up -d --remove-orphans

echo "Current state:"
docker compose ps

echo
echo "Run ./scripts/test-dns.sh to perform an end-to-end DNS test."
