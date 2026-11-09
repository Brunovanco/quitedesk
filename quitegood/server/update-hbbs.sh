#!/bin/bash
# Install the latest Quitegood hbbs build (release qg-server) and restart hbbs.
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
cd $DIR && docker compose up -d --force-recreate hbbs
sleep 4; docker logs --tail 12 qg-hbbs
