#!/bin/bash
# Quitegood Support - clean (re)install of the RustDesk OSS server behind nginx (443 only).
# Run on the server as root, with compose.yml and nginx-support.quitegood.be.conf next to it.
set -euo pipefail
DIR=/opt/quitegood-support
SRC="$(cd "$(dirname "$0")" && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)
BK=/root/rustdesk-backup-$STAMP

echo "== 1. Backup -> $BK.tgz"
mkdir -p $BK
for p in /var/lib/rustdesk-server /opt/rustdesk /home/quitegood/data /home/quitegood/compose.yml \
         /home/quitegood/docker-compose.yml /etc/nginx/sites-available /etc/nginx/sites-enabled \
         /etc/systemd/system/rustdesk-hbbs.service /etc/systemd/system/rustdesk-hbbr.service \
         /usr/bin/hbbs /usr/bin/hbbr /usr/bin/rustdesk-utils /var/log/rustdesk-server $DIR; do
  [ -e "$p" ] && cp -a --parents "$p" $BK/ || true
done
ufw status numbered > $BK/ufw-before.txt 2>&1 || true
tar czf $BK.tgz -C / "${BK#/}" && rm -rf $BK
ls -lh $BK.tgz

echo "== 2. Remove old RustDesk (systemd + docker)"
for s in rustdesk-hbbs rustdesk-hbbr; do systemctl disable --now $s 2>/dev/null || true; rm -f /etc/systemd/system/$s.service; done
systemctl daemon-reload
for d in /home/quitegood /opt/rustdesk; do
  for f in compose.yml docker-compose.yml; do
    [ -f $d/$f ] && (cd $d && docker compose -f $f down --remove-orphans 2>/dev/null) || true
  done
done
for c in hbbs hbbr rustdesk rustdesk-hbbs rustdesk-hbbr qg-hbbs qg-hbbr; do docker rm -f $c 2>/dev/null || true; done
rm -f /usr/bin/hbbs /usr/bin/hbbr /usr/bin/rustdesk-utils
rm -rf /var/lib/rustdesk-server /opt/rustdesk /var/log/rustdesk-server
rm -rf /home/quitegood/data /home/quitegood/compose.yml /home/quitegood/docker-compose.yml
rm -f /etc/nginx/sites-enabled/rustdesk.conf /etc/nginx/sites-available/rustdesk.conf /etc/nginx/sites-available/rustdesk.conf.bak
docker image rm rustdesk/rustdesk-server-pro:latest docker.io/rustdesk/rustdesk-server-pro:latest 2>/dev/null || true

echo "== 3. Deploy OSS server in $DIR"
mkdir -p $DIR/data
install -m 644 "$SRC/compose.yml" $DIR/compose.yml
cd $DIR
docker compose pull -q
docker compose up -d
for i in $(seq 1 20); do [ -s $DIR/data/id_ed25519.pub ] && break; sleep 2; done
docker compose ps

echo "== 4. nginx"
install -m 644 "$SRC/nginx-support.quitegood.be.conf" /etc/nginx/sites-available/support.quitegood.be
ln -sf /etc/nginx/sites-available/support.quitegood.be /etc/nginx/sites-enabled/support.quitegood.be
rm -f /etc/nginx/sites-enabled/default
mkdir -p /var/www/html
nginx -t
systemctl reload nginx

echo "== 5. Host firewall (ufw): only 22, 80, 443"
for r in 21114/tcp 21115/tcp 21116/tcp 21116/udp 21117/tcp 21118/tcp 21119/tcp 21115:21119/tcp; do
  ufw --force delete allow $r >/dev/null 2>&1 || true
done
ufw allow 22/tcp >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
ufw status

echo "== 6. Result"
echo "QG_SERVER_KEY=$(cat $DIR/data/id_ed25519.pub)"
