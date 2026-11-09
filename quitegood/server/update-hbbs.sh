#!/bin/bash
# Install the latest Quitegood hbbs build (release qg-server: WebSocket peer registration)
# and restart hbbs. Safe to re-run. Roll back: cp bin/hbbs.prev bin/hbbs && docker compose up -d --force-recreate hbbs
set -euo pipefail
DIR=/opt/quitegood-support
URL=https://github.com/Brunovanco/quitedesk/releases/download/qg-server
mkdir -p $DIR/bin && cd $DIR/bin
curl -fsSL -o hbbs.new $URL/hbbs-x86_64-musl
curl -fsSL -o hbbs.sha256 $URL/hbbs-x86_64-musl.sha256
echo "$(cut -d' ' -f1 hbbs.sha256)  hbbs.new" | sha256sum -c -
chmod 755 hbbs.new
[ -f hbbs ] && cp hbbs hbbs.prev
mv hbbs.new hbbs
cd $DIR
# mount the patched binary into the hbbs container (once)
if ! grep -q "./bin/hbbs:/usr/bin/hbbs" compose.yml; then
  cp compose.yml compose.yml.bak
  python3 - <<'PY'
p='compose.yml'; s=open(p).read()
anchor="    command: hbbs -r support.quitegood.be -k _\n    volumes:\n      - ./data:/root\n"
assert anchor in s, "compose.yml layout changed"
s=s.replace(anchor, anchor+"      - ./bin/hbbs:/usr/bin/hbbs:ro   # Quitegood hbbs (WebSocket registration)\n",1)
open(p,'w').write(s)
PY
fi
docker compose up -d --force-recreate hbbs
sleep 5
docker exec qg-hbbs hbbs --version 2>/dev/null || true
docker logs --tail 8 qg-hbbs
echo "OK - hbbs Quitegood installé"
