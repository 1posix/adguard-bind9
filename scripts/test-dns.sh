#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f .env ]] || { echo "Missing .env." >&2; exit 1; }
# shellcheck disable=SC1091
set -a
source ./.env
set +a

command -v dig >/dev/null 2>&1 || {
    echo "dig is required on the Debian host. Install it with: sudo apt install dnsutils" >&2
    exit 1
}

DNS="${DNS_BIND_IP}"

echo "== Containers =="
docker compose ps

echo
echo_resolver() {
    local domain="$1"
    echo "== Resolve ${domain} through AdGuard (${DNS}:53) =="
    dig +time=3 +tries=1 @"$DNS" "$domain" A
}

echo_resolver example.org

echo "== DNSSEC negative test =="
status="$(dig +time=3 +tries=1 +comments +noanswer +nostats @"$DNS" dnssec-failed.org A \
    | sed -n 's/.*status: \([^,]*\).*/\1/p' | head -n1)"

if [[ "$status" == "SERVFAIL" ]]; then
    echo "OK: dnssec-failed.org returned SERVFAIL; DNSSEC validation is active in the resolver path."
else
    echo "WARN: expected SERVFAIL for dnssec-failed.org, got '${status:-no status}'." >&2
    echo "Check AdGuard upstream and BIND DNSSEC settings." >&2
fi

echo
echo "== Optional filtering observation (does not fail the test) =="
dig +short +time=3 +tries=1 @"$DNS" doubleclick.net A || true

echo
echo "DNS smoke test finished."
