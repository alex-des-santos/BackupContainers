# Backup diário de configurações Docker (VPS → GitHub)

Backup diário de **configurações** Docker (compose, `docker inspect`, daemon, Caddyfile) da sua VPS para este repositório GitHub, com agendamento via cron na VPS e GitHub Actions.

---

## O que esta ferramenta faz e não faz

- **Faz:** encontra automaticamente todos os `docker-compose.yml` em `/home` e `/srv`, copia apenas os arquivos de configuração (compose, Dockerfile, prometheus.yml, Caddyfile, etc.), coleta o estado do Docker (ps, images, networks, volumes, inspect por container) e empacota tudo num tarball.
- **Não faz:** não inclui **dados de volumes** (bases de dados, uploads, assets, cache). O GitHub tem [limites de tamanho](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github) (aviso a partir de ~50 MiB, bloqueio em 100 MB por ficheiro) e versionar volumes aumenta o risco de expor segredos. Para backup de dados, use armazenamento próprio (S3, WebDAV, etc.).

---

## Pré-requisitos

- VPS Linux com Docker instalado.
- Acesso SSH à VPS por chave (recomendado: deploy key ou utilizador com permissões mínimas).
- Repositório GitHub (recomendado **privado**).
- Bash no servidor (script compatível com Bash 4+; testado em Debian/Ubuntu).

---

## Quick start

### 1. Instalar o script na VPS

```bash
# Copiar o script para a VPS
scp scripts/backup-docker-configs.sh usuario@sua-vps:/tmp/

# Na VPS: instalar e tornar executável
sudo mv /tmp/backup-docker-configs.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/backup-docker-configs.sh

# Criar diretório de backup persistente
sudo mkdir -p /var/backups/docker-configs
sudo chown $USER:$USER /var/backups/docker-configs
```

### 2. Testar o backup manualmente

```bash
sudo BACKUP_OUTPUT_DIR=/var/backups/docker-configs BACKUP_EXCLUDE_ENV=1 /usr/local/bin/backup-docker-configs.sh
```

Deve imprimir o path do tarball (ex.: `/var/backups/docker-configs/docker-config-backup-2026-03-04.tar.gz`).

### 3. Configurar o cron diário

Criar `/etc/cron.d/docker-backup` com o conteúdo:

```cron
# Backup diário de configurações Docker - 03:00 BRT (06:00 UTC)
BACKUP_OUTPUT_DIR=/var/backups/docker-configs
BACKUP_EXCLUDE_ENV=1
BACKUP_KEEP_DAYS=7
0 6 * * * root /usr/local/bin/backup-docker-configs.sh >> /var/log/docker-backup.log 2>&1
```

Garantir que o cron daemon está ativo:

```bash
sudo systemctl enable cron && sudo systemctl start cron
```

### 4. Configurar secrets no GitHub

Em **Settings → Secrets and variables → Actions** do repositório, criar:

| Secret | Valor |
|--------|-------|
| `VPS_HOST` | IP ou hostname da VPS (ex.: `arconde.cloud`) |
| `VPS_USER` | Usuário SSH (ex.: `admin_manus`) |
| `VPS_SSH_KEY` | Chave privada SSH completa (ed25519 recomendado) |
| `VPS_SSH_PORT` | Porta SSH (default: `22`) |

A chave pública correspondente deve estar em `~/.ssh/authorized_keys` na VPS.

### 5. Ativar o GitHub Actions

O workflow em `.github/workflows/daily-backup.yml` roda diariamente às **06:15 UTC (03:15 BRT)** e pode ser disparado manualmente em **Actions → daily-vps-config-backup → Run workflow**.

---

## Estrutura do backup

Cada arquivo `YYYY-MM-DD.tar.gz` contém:

```
docker-config-backup-YYYY-MM-DD/
├── compose_files/
│   ├── home/                              # /home/docker-compose.yml
│   ├── home_deploys_ecommerce-analytics/  # docker-compose.yml + configs
│   ├── home_deploys_jotty/
│   ├── home_deploys_karakeep/
│   ├── home_deploys_portabase/
│   └── home_admin_manus_ml-production-pipeline/
├── inspect/
│   ├── docker-ps.txt
│   ├── docker-images.txt
│   ├── docker-networks.txt
│   ├── docker-volumes.txt
│   ├── docker-stats.txt
│   └── containers/   # Um arquivo .json por container (docker inspect)
└── system/
    └── Caddyfile     # Configuração do reverse proxy Caddy
```

---

## Variáveis de ambiente

| Variável | Default | Descrição |
|----------|---------|-----------|
| `BACKUP_OUTPUT_DIR` | `/var/backups/docker-configs` | Diretório onde o script cria o tarball. |
| `BACKUP_EXCLUDE_ENV` | `1` | Se `1`, não inclui arquivos `.env` no tarball (recomendado). |
| `BACKUP_KEEP_DAYS` | `7` | Quantos dias manter backups locais antes de deletar. |

---

## Descobrir onde estão os compose

Na VPS, para listar possíveis diretórios com `docker-compose.yml`:

```bash
find /home /srv /opt -name "docker-compose.yml" 2>/dev/null
```

O script busca automaticamente em `/home`, `/srv` e `/opt` com profundidade máxima de 6 níveis.

---

## Agendamento

O cron no workflow está em **UTC**. Exemplo no arquivo: `15 6 * * *` = 06:15 UTC. Para Brasil (BRT, UTC-3) isso corresponde a 03:15. Pode alterar o cron em [.github/workflows/daily-backup.yml](.github/workflows/daily-backup.yml).

O [schedule do GitHub](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule) pode atrasar em repositórios sem atividade recente.

---

## Restore

1. Extrair o tarball: `tar -xzf backups/2026-03-04.tar.gz`
2. Dentro da pasta extraída:
   - **compose_files/** — use os `docker-compose.yml` para recriar os stacks; ajuste paths e `.env` conforme o novo servidor.
   - **inspect/** — referência do estado dos containers (ps, images, networks, volumes, inspect em JSON).
   - **system/Caddyfile** — configuração do reverse proxy, se existir.

---

## Segurança

- **Não versionar `.env`:** o script, por padrão, exclui `.env` do tarball (`BACKUP_EXCLUDE_ENV=1`). Mantenha-o assim para evitar segredos no repositório.
- **Repositório privado:** recomendado para que os backups não fiquem públicos.
- **SSH:** use uma chave dedicada (deploy key) ou um utilizador com permissões mínimas na VPS.

---

## Solução de problemas

| Problema | Possível causa | Sugestão |
|----------|----------------|----------|
| SSH connection refused | Porta errada ou firewall | Verificar `VPS_SSH_PORT` e regras de firewall na VPS. |
| Permission denied (publickey) | Chave incorreta ou não instalada | Verificar que o conteúdo de `VPS_SSH_KEY` está completo e que a chave pública está em `~/.ssh/authorized_keys` na VPS. |
| Script não encontrado | Script não instalado | Instalar em `/usr/local/bin/backup-docker-configs.sh` e `chmod +x`. |
| Tarball vazio ou muito pequeno | Nenhum compose encontrado | Verificar se há `docker-compose.yml` em `/home`, `/srv` ou `/opt`. |
| Backup muito grande | Dados de aplicação incluídos | Verificar se o script está na versão mais recente (deve copiar apenas arquivos de config). |
| Cron não executa | Daemon cron não instalado | `sudo apt-get install -y cron && sudo systemctl enable cron && sudo systemctl start cron` |

---

## Licença

Este projeto está sob a licença MIT. Ver [LICENSE](LICENSE).
