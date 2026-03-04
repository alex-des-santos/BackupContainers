# Backup diário de configurações Docker (VPS → GitHub)

Backup diário de **configurações** Docker (compose, `docker inspect`, daemon) da sua VPS para um repositório GitHub, com agendamento via GitHub Actions.

---

## O que esta ferramenta faz e não faz

- **Faz:** recolhe ficheiros de configuração (docker-compose, daemon.json) e estado do Docker (ps, images, networks, volumes, inspect) num tarball e envia-o para este repositório (ou apenas gera o tarball na VPS para a Action baixar).
- **Não faz:** não inclui **dados de volumes** (bases de dados, uploads, etc.). O GitHub tem [limites de tamanho](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github) (aviso a partir de ~50 MiB, bloqueio em 100 MB por ficheiro) e versionar volumes aumenta o risco de expor segredos. Para backup de dados, use armazenamento próprio (S3, WebDAV, etc.).

---

## Pré-requisitos

- VPS Linux com Docker instalado.
- Acesso SSH à VPS por chave (recomendado: deploy key ou utilizador com permissões mínimas).
- Repositório GitHub (recomendado **privado**).
- Bash no servidor (script compatível com Bash 4+; testado em Ubuntu/Debian).

---

## Quick start

1. **Clonar este repositório** (ou fazer fork e clonar o seu fork).

2. **Configurar secrets no GitHub:** em **Settings → Secrets and variables → Actions**, criar:
   - `VPS_HOST` — IP ou hostname da VPS
   - `VPS_USER` — utilizador SSH (ex.: `root`, `ubuntu`)
   - `VPS_SSH_KEY` — chave privada SSH completa
   - `VPS_SSH_PORT` — (opcional) porta SSH, default 22

   Ver referência em [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

3. **Instalar o script na VPS:** copiar `scripts/backup-docker-configs.sh` para a VPS e colocá-lo em `/usr/local/bin`:
   ```bash
   scp -P 22 scripts/backup-docker-configs.sh utilizador@sua-vps:/tmp/
   ssh utilizador@sua-vps "sudo mv /tmp/backup-docker-configs.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/backup-docker-configs.sh"
   ```

4. **Definir `BACKUP_COMPOSE_ROOT` na VPS:** esse é o diretório onde estão os seus `docker-compose.yml`. Pode defini-lo em `/etc/environment` (ex.: `BACKUP_COMPOSE_ROOT=/srv/docker`) ou exportá-lo antes de rodar o script. Ver [Descobrir onde estão os compose](#descobrir-onde-estão-os-compose).

5. **Testar o backup manualmente na VPS:**
   ```bash
   export BACKUP_COMPOSE_ROOT=/srv/docker   # ajuste ao seu path
   sudo /usr/local/bin/backup-docker-configs.sh
   ```
   Deve imprimir o path do tarball (ex.: `/tmp/docker-config-backup-2025-03-03.tar.gz`).

6. **Fazer push do workflow:** ao subir o ficheiro `.github/workflows/daily-backup.yml` (ou ao ativar o schedule no branch padrão), o backup agendado passa a correr diariamente. Pode também disparar manualmente em **Actions → daily-vps-config-backup → Run workflow**.

   Por defeito a pasta `backups/` está no `.gitignore`. Se quiser **histórico de backups no Git**, remova `backups/` do [.gitignore](.gitignore) (o GitHub tem limite de 100 MB por ficheiro; só configs costuma ficar abaixo).

---

## Descobrir onde estão os compose

Na VPS, para listar possíveis diretórios com `docker-compose.yml`:

```bash
find / -name "docker-compose.yml" 2>/dev/null
```

Use um dos diretórios pai (por exemplo a pasta que contém vários projetos) como `BACKUP_COMPOSE_ROOT`. Se usar um provedor como Hostinger, consulte a documentação deles sobre onde os projetos/containers são guardados.

---

## Configuração detalhada

- **Variáveis de ambiente e secrets:** [docs/CONFIGURATION.md](docs/CONFIGURATION.md)
- **Exemplo de configuração:** copie [config.example](config.example) e adapte (não commite ficheiros com dados reais).

---

## Agendamento

O cron no workflow está em **UTC**. Exemplo no ficheiro: `15 6 * * *` = 06:15 UTC. Para Brasil (BRT, UTC-3) isso corresponde a 03:15. Pode alterar o cron em [.github/workflows/daily-backup.yml](.github/workflows/daily-backup.yml).  
O [schedule do GitHub](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule) pode atrasar em repositórios sem atividade recente.

---

## Restore

1. Extrair o tarball (ex.: `tar -xzf backups/2025-03-03.tar.gz`).
2. Dentro da pasta extraída:
   - **compose/** — use os `docker-compose.yml` (e ficheiros relacionados) para recriar os stacks; ajuste paths e `.env` conforme o novo servidor.
   - **inspect/** — referência do estado dos containers (ps, images, networks, volumes, inspect em JSON).
   - **system/daemon.json** — configuração do daemon Docker, se existir.

---

## Segurança

- **Não versionar `.env`:** o script, por defeito, exclui `.env` do tarball (`BACKUP_EXCLUDE_ENV=1`). Mantenha-o assim para evitar segredos no repositório.
- **Repositório privado:** recomendado para que os backups (que podem conter nomes de serviços e configuração) não fiquem públicos.
- **SSH:** use uma chave dedicada (deploy key) ou um utilizador com permissões mínimas na VPS.

---

## Solução de problemas

| Problema | Possível causa | Sugestão |
|----------|----------------|----------|
| SSH connection refused | Porta errada ou firewall | Verificar `VPS_SSH_PORT` e regras de firewall na VPS. |
| Permission denied (publickey) | Chave incorreta ou não instalada na VPS | Verificar que o conteúdo de `VPS_SSH_KEY` está completo e que a chave pública está em `~/.ssh/authorized_keys` na VPS. |
| Script não encontrado / Permission denied | Script não instalado ou sem execução | Instalar em `/usr/local/bin/backup-docker-configs.sh` e `chmod +x`. |
| Tarball não encontrado no step de download | Script falhou ou path diferente | Rodar o workflow manualmente (Actions → Run workflow) e ver os logs; confirmar que na VPS o script imprime o path do tarball e que `BACKUP_OUTPUT_DIR` (se usado) está acessível. |
| Nada em `compose/` no tarball | `BACKUP_COMPOSE_ROOT` errado ou diretório inexistente | Definir `BACKUP_COMPOSE_ROOT` no ambiente da VPS e verificar com `find / -name "docker-compose.yml"`. |

---

## Licença

Este projeto está sob a licença MIT. Ver [LICENSE](LICENSE).
