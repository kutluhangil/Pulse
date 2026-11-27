#!/usr/bin/env bash
# Install or update the Pulse agent on the home server. Runs on the Mac.
#
#   ./deploy/deploy.sh              build on the server, start, publish to the tailnet
#   ./deploy/deploy.sh --copy-token copy the app token to the clipboard (never printed)
#
# Needs: Docker context "macmini", SSH key access to the server, Tailscale on both.
set -euo pipefail

SERVER="${PULSE_SERVER:-kutluhan@macmini-server}"
CONTEXT="${PULSE_DOCKER_CONTEXT:-macmini}"
TS_HOST="${PULSE_TS_HOST:-macmini-server.taild883a6.ts.net}"
PORT=9123

cd "$(dirname "$0")"
ENV_FILE=.env

if [[ "${1:-}" == "--copy-token" ]]; then
  grep '^PULSE_TOKEN=' "$ENV_FILE" | cut -d= -f2- | tr -d '\n' | pbcopy
  echo "Token copied to the clipboard."
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  (umask 077; sed "s/^PULSE_TOKEN=.*/PULSE_TOKEN=$(openssl rand -hex 32)/" .env.example > "$ENV_FILE")
  echo "Created deploy/.env with a new token (git-ignored)."
fi
git check-ignore -q "$ENV_FILE" || { echo "deploy/.env is not git-ignored, aborting." >&2; exit 1; }

PULSE_VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"
export PULSE_VERSION

echo "==> Building and starting on $CONTEXT ($PULSE_VERSION)"
docker --context "$CONTEXT" compose --env-file "$ENV_FILE" -f compose.yaml up -d --build --remove-orphans

echo "==> Waiting for the agent"
for _ in $(seq 1 30); do
  if ssh -o BatchMode=yes "$SERVER" "curl -fsS http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
ssh -o BatchMode=yes "$SERVER" "curl -fsS http://127.0.0.1:$PORT/health" >/dev/null

echo "==> Publishing to the tailnet (tailscale serve, tailnet only)"
ssh -o BatchMode=yes "$SERVER" "tailscale serve --bg --https=$PORT http://127.0.0.1:$PORT" >/dev/null

echo "==> Verifying https://$TS_HOST:$PORT"
TOKEN="$(grep '^PULSE_TOKEN=' "$ENV_FILE" | cut -d= -f2-)"
code=$(curl -s -o /dev/null -w '%{http_code}' "https://$TS_HOST:$PORT/v1/snapshot")
[[ "$code" == "401" ]] || { echo "Expected 401 without a token, got $code" >&2; exit 1; }
curl -fsS -H "Authorization: Bearer $TOKEN" "https://$TS_HOST:$PORT/v1/snapshot" \
  | python3 -I -c '
import json, sys
s = json.load(sys.stdin)
print("   health %d %s · cpu %.1f%% · %.0f°C · %d containers · agent %s" % (
    s["health"]["score"], s["health"]["label"], s["cpu"]["usage"],
    s["thermal"]["packageC"], len(s["containers"]), s["host"]["agentVersion"]))'
echo "Done. App address: https://$TS_HOST:$PORT   Token: ./deploy/deploy.sh --copy-token"
