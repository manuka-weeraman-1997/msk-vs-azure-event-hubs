#!/usr/bin/env bash
# Check DNS resolution and a TCP + TLS handshake to the Kafka endpoint.
# Uses no credentials, so it only proves network reachability, not auth.
#
# Env: KAFKA_PLATFORM (msk | eventhubs)
#      KAFKA_BOOTSTRAP_SERVERS (host:port[,host:port...]) or, for Event Hubs,
#      EVENTHUBS_NAMESPACE (builds <namespace>.servicebus.windows.net:9093)
set -euo pipefail

PLATFORM="${KAFKA_PLATFORM:-}"
case "$PLATFORM" in
  msk | eventhubs) ;;
  *)
    echo "ERROR: set KAFKA_PLATFORM to 'msk' or 'eventhubs'." >&2
    exit 2
    ;;
esac

BOOTSTRAP="${KAFKA_BOOTSTRAP_SERVERS:-}"
if [ -z "$BOOTSTRAP" ] && [ "$PLATFORM" = "eventhubs" ] && [ -n "${EVENTHUBS_NAMESPACE:-}" ]; then
  BOOTSTRAP="${EVENTHUBS_NAMESPACE}.servicebus.windows.net:9093"
fi
if [ -z "$BOOTSTRAP" ]; then
  echo "ERROR: set KAFKA_BOOTSTRAP_SERVERS (or EVENTHUBS_NAMESPACE for Event Hubs)." >&2
  exit 2
fi

resolve() {
  local host="$1"
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$host" | awk '{print $1}' | head -n 1
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '/^Address/ {print $NF}' | tail -n 1
  elif command -v dig >/dev/null 2>&1; then
    dig +short "$host" | head -n 1
  else
    return 1
  fi
}

tls_check() {
  local host="$1" port="$2"
  if command -v openssl >/dev/null 2>&1; then
    if echo | openssl s_client -connect "${host}:${port}" -servername "$host" \
      -brief >/dev/null 2>&1 </dev/null; then
      return 0
    fi
    return 1
  elif command -v nc >/dev/null 2>&1; then
    nc -z -w 5 "$host" "$port" >/dev/null 2>&1
  else
    echo "  neither openssl nor nc found" >&2
    return 2
  fi
}

failures=0
echo "Platform: $PLATFORM"
IFS=',' read -r -a ENDPOINTS <<<"$BOOTSTRAP"
for endpoint in "${ENDPOINTS[@]}"; do
  endpoint="${endpoint// /}"
  host="${endpoint%:*}"
  port="${endpoint##*:}"
  echo "Endpoint: $host:$port"

  ip="$(resolve "$host" || true)"
  if [ -n "$ip" ]; then
    echo "  DNS:  OK ($ip)"
  else
    echo "  DNS:  FAIL (cannot resolve $host)"
    failures=$((failures + 1))
    continue
  fi

  if tls_check "$host" "$port"; then
    echo "  TCP/TLS: OK"
  else
    echo "  TCP/TLS: FAIL (blocked by firewall, security group, NSG or private endpoint?)"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "Result: $failures check(s) failed. See docs/troubleshooting.md."
  exit 1
fi
echo "Result: all checks passed. Authentication is not tested here."
