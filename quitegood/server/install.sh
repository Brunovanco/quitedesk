#!/bin/bash
# Quitegood Support - (ré)installation propre du serveur RustDesk OSS derrière Caddy (443 uniquement).
# Usage sur le serveur :  sudo bash install.sh   (les fichiers compose.yml et Caddyfile à côté)
set -euo pipefail
DIR=/opt/quitegood-support
STAMP=$(date +%Y%m%d-%H%M%S)
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "== 1. Sauvegarde et arrêt de l'ancien RustDesk"
mkdir -p /root/rustdesk-backup-$STAMP
if command -v docker >/dev/null; then
  for c in $(docker ps -a --format '{{.Names}} {{.Image}}' | awk '/rustdesk|hbbs|hbbr/ {print $1}'); do
    docker inspect "$c" > /root/rustdesk-backup-$STAMP/$c.inspect.json || true
    docker rm -f "$c" || true
  done
fi
for s in $(systemctl list-unit-files --no-legend 2>/dev/null | awk '/hbbs|hbbr|rustdesk/ {print $1}'); do
  systemctl disable --now "$s" || true
done
for f in $(find / -xdev -name 'id_ed25519*' -path '*' -not -path '/root/.ssh/*' -not -path '/home/*/.ssh/*' -not -path '/proc/*' -not -path "$DIR/*" 2>/dev/null); do
  cp --parents "$f" /root/rustdesk-backup-$STAMP/ || true
done
echo "   sauvegarde : /root/rustdesk-backup-$STAMP"

echo "== 2. Docker"
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

echo "== 3. Déploiement dans $DIR"
mkdir -p $DIR/data
install -m 644 "$SRC/compose.yml" $DIR/compose.yml
install -m 644 "$SRC/Caddyfile"   $DIR/Caddyfile
cd $DIR
docker compose pull
docker compose up -d
sleep 8
docker compose ps

echo "== 4. Pare-feu local (si ufw actif) : 22, 80, 443"
if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp
  for p in 21114 21115 21116 21117 21118 21119; do ufw delete allow $p/tcp 2>/dev/null || true; done
  ufw delete allow 21116/udp 2>/dev/null || true
fi

echo "== 5. Clé publique du serveur (à mettre dans la variable GitHub QG_SERVER_KEY)"
for i in $(seq 1 15); do [ -s $DIR/data/id_ed25519.pub ] && break; sleep 2; done
echo "QG_SERVER_KEY=$(cat $DIR/data/id_ed25519.pub)"
