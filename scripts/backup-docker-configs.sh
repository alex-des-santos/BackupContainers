#!/usr/bin/env bash
#
# Backup de configurações Docker (compose, inspect, daemon) para um tarball.
# Inclui: árvore de compose em BACKUP_COMPOSE_ROOT, daemon.json, e saídas de
# docker ps/images/network/volume/inspect. NÃO inclui dados de volumes.
#
# Variáveis de ambiente:
#   BACKUP_COMPOSE_ROOT  Diretório com docker-compose.yml (default: /srv/docker)
#   BACKUP_OUTPUT_DIR    Onde criar o tarball (default: /tmp)
#   BACKUP_EXCLUDE_ENV   Se 1, exclui arquivos .env do backup (recomendado)
#
# Uso:
#   export BACKUP_COMPOSE_ROOT=/home/meu/apps
#   ./backup-docker-configs.sh
#   # Imprime o path do tarball gerado, ex.: /tmp/docker-config-backup-2025-03-03.tar.gz
#
# Instalação na VPS: copiar para /usr/local/bin e definir as variáveis
# (ex.: em /etc/environment ou no cron que chama este script).
#
set -euo pipefail

OUT_BASE="${BACKUP_OUTPUT_DIR:-/tmp}"
COMPOSE_ROOT="${BACKUP_COMPOSE_ROOT:-/srv/docker}"
EXCLUDE_ENV="${BACKUP_EXCLUDE_ENV:-1}"
DATE="$(date -u +%F)"
DEST="${OUT_BASE}/docker-config-backup-${DATE}"
TARBALL="${OUT_BASE}/docker-config-backup-${DATE}.tar.gz"

rm -rf "$DEST"
mkdir -p "$DEST"/{compose,inspect,system}
mkdir -p "$DEST/inspect/containers"

# 1) Árvore de compose (opcional: excluir .env)
if [[ -d "$COMPOSE_ROOT" ]]; then
  if [[ "$EXCLUDE_ENV" == "1" ]]; then
    rsync -a --delete --exclude='.env' "$COMPOSE_ROOT/" "$DEST/compose/" 2>/dev/null || cp -a "$COMPOSE_ROOT"/* "$DEST/compose/" 2>/dev/null || true
  else
    rsync -a --delete "$COMPOSE_ROOT/" "$DEST/compose/" 2>/dev/null || cp -a "$COMPOSE_ROOT"/* "$DEST/compose/" 2>/dev/null || true
  fi
fi

# 2) Config do Docker daemon
if [[ -f /etc/docker/daemon.json ]]; then
  cp -a /etc/docker/daemon.json "$DEST/system/"
fi

# 3) Estado do Docker (não inclui dados de volumes)
docker ps -a --no-trunc > "$DEST/inspect/docker-ps.txt" 2>/dev/null || true
docker images --digests > "$DEST/inspect/docker-images.txt" 2>/dev/null || true
docker network ls > "$DEST/inspect/docker-networks.txt" 2>/dev/null || true
docker volume ls > "$DEST/inspect/docker-volumes.txt" 2>/dev/null || true

# 4) Inspect detalhado por container
for c in $(docker ps -aq 2>/dev/null); do
  docker inspect "$c" > "$DEST/inspect/containers/$c.json" 2>/dev/null || true
done

# 5) Tarball (um nível acima do DEST para o nome do diretório interno ser a data)
tar -C "$OUT_BASE" -czf "$TARBALL" "docker-config-backup-${DATE}"
rm -rf "$DEST"

echo "$TARBALL"
