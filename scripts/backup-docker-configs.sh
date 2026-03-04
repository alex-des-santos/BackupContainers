#!/usr/bin/env bash
#
# Backup de configurações Docker (compose, inspect, daemon) para um tarball.
# Inclui: docker-compose.yml e arquivos de config relacionados, daemon.json,
# e saídas de docker ps/images/network/volume/inspect.
# NÃO inclui dados de volumes, databases, assets, cache ou .env.
#
# Variáveis de ambiente:
#   BACKUP_OUTPUT_DIR    Onde criar o tarball (default: /var/backups/docker-configs)
#   BACKUP_EXCLUDE_ENV   Se 1, exclui arquivos .env do backup (recomendado, default: 1)
#   BACKUP_KEEP_DAYS     Quantos dias manter backups locais (default: 7)
#
# Uso:
#   sudo /usr/local/bin/backup-docker-configs.sh
#   # Imprime o path do tarball gerado
#
# Instalação: /usr/local/bin/backup-docker-configs.sh (chmod +x)
#
set -euo pipefail

OUT_BASE="${BACKUP_OUTPUT_DIR:-/var/backups/docker-configs}"
EXCLUDE_ENV="${BACKUP_EXCLUDE_ENV:-1}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"
DATE="$(date -u +%F)"
DEST="${OUT_BASE}/docker-config-backup-${DATE}"
TARBALL="${OUT_BASE}/docker-config-backup-${DATE}.tar.gz"

# Extensões e arquivos de configuração a incluir
CONFIG_EXTENSIONS=(
    "docker-compose.yml"
    "docker-compose.yaml"
    "compose.yml"
    "compose.yaml"
    "Dockerfile"
    "Dockerfile.*"
    ".dockerignore"
    "*.conf"
    "*.ini"
    "*.toml"
    "prometheus.yml"
    "prometheus.yaml"
    "nginx.conf"
    "Caddyfile"
    "Caddyfile.*"
    "*.env.example"
    "*.env.sample"
    "*.env.template"
)

# Pastas a excluir (dados, cache, venv, git, etc.)
EXCLUDE_DIRS=(
    "data"
    "cache"
    "volumes"
    "node_modules"
    "venv"
    ".venv"
    "__pycache__"
    ".git"
    "mlruns"
    "mlartifacts"
    "notebooks"
    "tests"
    "src"
    "bin"
    "lib"
    "include"
    "share"
    "backups"
    "logs"
    "tmp"
    "temp"
    "uploads"
    "assets"
    "static"
    "media"
    "dist"
    "build"
    ".npm"
    ".npm-global"
    ".cache"
    ".local"
    ".config"
    ".dotnet"
    ".vscode-server"
    "painel-conciliacao"
    "ecommerce-data-analysis"
    "ml-churn-prediction"
)

echo "[INFO] Iniciando backup de configurações Docker - $DATE"
echo "[INFO] Destino: $TARBALL"

mkdir -p "$DEST"/{compose_files,inspect,system}
mkdir -p "$DEST/inspect/containers"

# -------------------------------------------------------
# 1) Encontrar todos os diretórios com docker-compose.yml
# -------------------------------------------------------
echo "[INFO] Procurando por arquivos docker-compose.yml..."

COMPOSE_DIRS=""
while IFS= read -r f; do
    dir=$(dirname "$f")
    # Filtrar caminhos indesejados
    if echo "$dir" | grep -qE '(/proc|/sys|/var/lib/docker/volumes/portainer_data/_data/Files|/var/lib/docker/volumes/portainer_data/_data/custom_templates)'; then
        continue
    fi
    COMPOSE_DIRS="$COMPOSE_DIRS
$dir"
done < <(find /home /srv /opt -maxdepth 6 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) 2>/dev/null)

# Remover duplicatas e linhas vazias
COMPOSE_DIRS=$(echo "$COMPOSE_DIRS" | sort -u | grep -v '^$')

if [ -z "$COMPOSE_DIRS" ]; then
    echo "[WARN] Nenhum arquivo docker-compose.yml encontrado."
else
    echo "[INFO] Diretórios compose encontrados:"
    echo "$COMPOSE_DIRS"

    while IFS= read -r path; do
        # Nome de destino seguro
        target_name=$(echo "$path" | sed 's|^/||' | sed 's|/|_|g')
        target_dir="$DEST/compose_files/$target_name"
        echo "[INFO] Copiando configs de: $path"
        mkdir -p "$target_dir"

        # Copiar apenas arquivos de configuração do diretório raiz do projeto
        for pattern in "${CONFIG_EXTENSIONS[@]}"; do
            # Copiar arquivos que correspondem ao padrão (apenas no nível raiz)
            for f in "$path"/$pattern; do
                [ -f "$f" ] || continue
                cp -a "$f" "$target_dir/" 2>/dev/null || true
            done
        done

        # Se BACKUP_EXCLUDE_ENV=0, incluir .env
        if [[ "$EXCLUDE_ENV" != "1" ]]; then
            [ -f "$path/.env" ] && cp -a "$path/.env" "$target_dir/" 2>/dev/null || true
        fi

    done <<< "$COMPOSE_DIRS"
fi

# -------------------------------------------------------
# 2) Config do Docker daemon
# -------------------------------------------------------
if [[ -f /etc/docker/daemon.json ]]; then
    echo "[INFO] Copiando /etc/docker/daemon.json"
    cp -a /etc/docker/daemon.json "$DEST/system/"
fi

# Caddyfile ativo
if [[ -f /etc/caddy/Caddyfile ]]; then
    echo "[INFO] Copiando /etc/caddy/Caddyfile"
    cp -a /etc/caddy/Caddyfile "$DEST/system/Caddyfile"
fi

# -------------------------------------------------------
# 3) Estado do Docker (não inclui dados de volumes)
# -------------------------------------------------------
echo "[INFO] Coletando estado do Docker (ps, images, networks, volumes)"
docker ps -a --no-trunc                                          > "$DEST/inspect/docker-ps.txt"          2>/dev/null || true
docker images --digests                                          > "$DEST/inspect/docker-images.txt"       2>/dev/null || true
docker network ls                                                > "$DEST/inspect/docker-networks.txt"     2>/dev/null || true
docker volume ls                                                 > "$DEST/inspect/docker-volumes.txt"      2>/dev/null || true
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" > "$DEST/inspect/docker-stats.txt" 2>/dev/null || true

# -------------------------------------------------------
# 4) Inspect detalhado por container
# -------------------------------------------------------
echo "[INFO] Coletando inspect de cada container"
CONTAINERS=$(docker ps -aq 2>/dev/null || true)
if [ -n "$CONTAINERS" ]; then
    for c in $CONTAINERS; do
        name=$(docker inspect --format='{{.Name}}' "$c" 2>/dev/null | tr -d '/' || echo "$c")
        docker inspect "$c" > "$DEST/inspect/containers/${name}.json" 2>/dev/null || true
    done
fi

# -------------------------------------------------------
# 5) Tarball
# -------------------------------------------------------
echo "[INFO] Criando tarball: $TARBALL"
tar -C "$OUT_BASE" -czf "$TARBALL" "docker-config-backup-${DATE}"
rm -rf "$DEST"

# -------------------------------------------------------
# 6) Limpeza de backups antigos
# -------------------------------------------------------
echo "[INFO] Removendo backups com mais de $KEEP_DAYS dias"
find "$OUT_BASE" -name "docker-config-backup-*.tar.gz" -mtime +"$KEEP_DAYS" -delete 2>/dev/null || true

echo "[SUCCESS] Backup concluído: $TARBALL"
echo "$TARBALL"
