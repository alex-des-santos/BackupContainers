#!/usr/bin/env bash
#
# Backup aprimorado de configurações Docker para um tarball.
# Encontra e inclui múltiplos docker-compose.yml, inspect, e daemon.json.
# NÃO inclui dados de volumes.
#
# Variáveis de ambiente:
#   BACKUP_OUTPUT_DIR    Onde criar o tarball (default: /tmp)
#   BACKUP_EXCLUDE_ENV   Se 1, exclui arquivos .env do backup (recomendado, default: 1)
#
set -euo pipefail

OUT_BASE="${BACKUP_OUTPUT_DIR:-/tmp}"
EXCLUDE_ENV="${BACKUP_EXCLUDE_ENV:-1}"
DATE="$(date -u +%F)"
DEST="${OUT_BASE}/docker-config-backup-${DATE}"
TARBALL="${OUT_BASE}/docker-config-backup-${DATE}.tar.gz"

echo "[INFO] Criando diretório de backup em $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"/{compose_files,inspect,system}
mkdir -p "$DEST/inspect/containers"

# 1) Encontrar e copiar todos os diretórios com docker-compose.yml
echo "[INFO] Procurando por arquivos docker-compose.yml..."
COMPOSE_FILES=$(find /home /srv /opt -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" 2>/dev/null | grep -v "/var/lib/docker/")

if [ -z "$COMPOSE_FILES" ]; then
    echo "[WARN] Nenhum arquivo docker-compose.yml encontrado."
else
    echo "[INFO] Arquivos compose encontrados:"
    echo "$COMPOSE_FILES"
    
    SAVE_IFS=$IFS
    IFS=$'\n'
    for f in $COMPOSE_FILES; do
        path=$(dirname "$f")
        # Usar um nome de destino seguro, substituindo / por _
        target_name=$(echo "$path" | sed 's/\//_/g' | sed 's/^_//')
        target_dir="$DEST/compose_files/$target_name"
        echo "[INFO] Copiando $path para $target_dir"
        mkdir -p "$target_dir"
        
        if [[ "$EXCLUDE_ENV" == "1" ]]; then
            rsync -a --exclude=".env" --exclude=".git" "$path/" "$target_dir/" 2>/dev/null || cp -a "$path"/* "$target_dir/" 2>/dev/null || true
        else
            rsync -a --exclude=".git" "$path/" "$target_dir/" 2>/dev/null || cp -a "$path"/* "$target_dir/" 2>/dev/null || true
        fi
    done
    IFS=$SAVE_IFS
fi

# 2) Config do Docker daemon
if [[ -f /etc/docker/daemon.json ]]; then
  echo "[INFO] Copiando /etc/docker/daemon.json"
  cp -a /etc/docker/daemon.json "$DEST/system/"
fi

# 3) Estado do Docker (não inclui dados de volumes)
echo "[INFO] Coletando estado do Docker (ps, images, networks, volumes)"
docker ps -a --no-trunc > "$DEST/inspect/docker-ps.txt" 2>/dev/null || true
docker images --digests > "$DEST/inspect/docker-images.txt" 2>/dev/null || true
docker network ls > "$DEST/inspect/docker-networks.txt" 2>/dev/null || true
docker volume ls > "$DEST/inspect/docker-volumes.txt" 2>/dev/null || true

# 4) Inspect detalhado por container
echo "[INFO] Coletando inspect de cada container"
CONTAINERS=$(docker ps -aq 2>/dev/null)
if [ -n "$CONTAINERS" ]; then
    for c in $CONTAINERS; do
      docker inspect "$c" > "$DEST/inspect/containers/$c.json" 2>/dev/null || true
    done
fi

# 5) Tarball
echo "[INFO] Criando tarball em $TARBALL"
tar -C "$OUT_BASE" -czf "$TARBALL" "docker-config-backup-${DATE}"
rm -rf "$DEST"

echo "[SUCCESS] Backup concluído: $TARBALL"
