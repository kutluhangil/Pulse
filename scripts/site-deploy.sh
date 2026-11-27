#!/bin/zsh
# Builds and tests the Pulse site (site/), then runs it on macmini-server behind
# Cloudflare Tunnel: pulse-site -> https://pulse.kutluhangil.dev. No ports are opened.
#   scripts/site-deploy.sh
# The tunnel token lives in site/deploy/tunnel.env (outside git). No commit or push here.
set -euo pipefail
site=${0:A:h:h}/site
[[ -f $site/deploy/tunnel.env ]] || { echo "site/deploy/tunnel.env missing (sunucu-yayin skill, step 2)" >&2; exit 1; }

cd "$site"
npm ci --silent
npx astro build
npm test
npx astro preview stop >/dev/null 2>&1 || true
npx astro preview --port 4330 --background >/dev/null
trap 'npx astro preview stop >/dev/null 2>&1 || true' EXIT
npx playwright test

echo "→ macmini-server: building the image and starting it"
docker --context macmini compose -f deploy/compose.yaml up -d --build

echo "→ https://pulse.kutluhangil.dev/health"
for i in {1..20}; do
  if curl -fsS --max-time 5 https://pulse.kutluhangil.dev/health >/dev/null 2>&1; then
    echo "live: https://pulse.kutluhangil.dev"
    exit 0
  fi
  sleep 3
done
echo "health check failed; logs: docker --context macmini logs pulse-site-cloudflared-1 | tail" >&2
exit 1
