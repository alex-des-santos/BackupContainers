# Referência de configuração

Documento de referência para reproduzir ou adaptar o backup de configurações Docker (VPS → GitHub).

---

## Variáveis de ambiente (VPS)

Definir na VPS antes de executar o script (ou no ambiente onde o script roda, ex.: cron, systemd).

| Variável | Obrigatório | Default | Descrição |
|----------|-------------|---------|-----------|
| `BACKUP_COMPOSE_ROOT` | Não | `/srv/docker` | Diretório que contém os seus `docker-compose.yml` (e subpastas por stack). |
| `BACKUP_OUTPUT_DIR` | Não | `/tmp` | Diretório onde o script cria o tarball (ex.: `/tmp/docker-config-backup-YYYY-MM-DD.tar.gz`). |
| `BACKUP_EXCLUDE_ENV` | Não | `1` | Se `1`, exclui ficheiros `.env` do tarball (recomendado). Qualquer outro valor inclui `.env`. |

**Onde definir na VPS:**

- **Cron:** `BACKUP_COMPOSE_ROOT=/home/meu/apps /usr/local/bin/backup-docker-configs.sh`
- **Ficheiro de ambiente:** adicionar em `/etc/environment` (ou `~/.bashrc` se rodar com utilizador específico) e fazer `source` antes do script.
- **Systemd:** na unidade de serviço, `Environment=BACKUP_COMPOSE_ROOT=/srv/docker`.

---

## Secrets do GitHub

Configurar em **Settings → Secrets and variables → Actions** do repositório.

| Secret | Obrigatório | Descrição |
|--------|-------------|-----------|
| `VPS_HOST` | Sim | IP ou nome DNS da VPS (ex.: `123.45.67.89` ou `vps.seudominio.com`). |
| `VPS_USER` | Sim | Utilizador SSH (ex.: `root`, `ubuntu`). |
| `VPS_SSH_KEY` | Sim | Conteúdo da chave privada SSH (inteira, incluindo `-----BEGIN ... -----`). Preferir deploy key ou utilizador com permissões mínimas. |
| `VPS_SSH_PORT` | Não | Porta SSH (default: `22`). |

---

## Agendamento (cron no workflow)

O workflow usa a sintaxe de [scheduled workflows](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule) do GitHub. O horário é sempre **UTC**.

| Exemplo | Significado |
|---------|-------------|
| `15 6 * * *` | Todos os dias às 06:15 UTC (ex.: 03:15 no Brasil, UTC-3). |
| `0 */12 * * *` | A cada 12 horas (00:00 e 12:00 UTC). |
| `0 0 * * *` | Uma vez por dia à meia-noite UTC. |

Para converter UTC para o seu fuso: [timezone converter](https://www.timeanddate.com/worldclock/converter.html).  
Nota: o agendamento depende da atividade no repositório (último commit no branch padrão); repositórios inativos podem ter o schedule atrasado.

---

## Estrutura do tarball

Cada ficheiro `YYYY-MM-DD.tar.gz` contém uma pasta com o seguinte layout:

```
docker-config-backup-YYYY-MM-DD/
├── compose/          # Cópia da árvore em BACKUP_COMPOSE_ROOT (ex.: docker-compose.yml por stack)
├── inspect/
│   ├── docker-ps.txt
│   ├── docker-images.txt
│   ├── docker-networks.txt
│   ├── docker-volumes.txt
│   └── containers/   # Um ficheiro .json por container (docker inspect)
└── system/
    └── daemon.json   # Cópia de /etc/docker/daemon.json (se existir)
```

**Restore:** extrair o tarball e usar `compose/` para reaplicar os stacks; `inspect/` e `system/` servem como referência do estado dos containers e da configuração do daemon.
