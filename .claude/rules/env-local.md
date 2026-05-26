---
name: env-local
description: Формат и правила ./.env.local — локальный gitignored файл рабочей станции с connection к VPS (SSH_HOST/PORT/USER/PROJECT_NAME или HOST=) и токенами, которые юзер кидает в чат. Host берётся отсюда, не хардкодится. Доступ к значению — через tools (grep в bash), не цитированием в чат. Грузится при работе с .env.local или scripts/tools/ssh.sh.
paths:
  - ".env.local"
  - ".env.local.example"
  - "scripts/tools/ssh.sh"
---

# Workstation creds — .env.local

`./.env.local` живёт **на рабочей станции оператора** и хранит то, что нужно для ops по VPS из
этого репо: **connection** к серверу + любые **токены**, которые оператор присылает. Это **не**
runtime-секреты приложения и **не** серверный `.env`:

| Файл | Где | Что |
|---|---|---|
| `.env.local` | workstation, gitignored | SSH connection (`SSH_HOST`/`SSH_PORT`/`SSH_USER`/`PROJECT_NAME` или `HOST=user@ip`) + токены оператора |
| `.env` | **только на VPS** | runtime identity+bootstrap (`PROJECT_NAME`/`ENV`/`DOMAIN`/`VAULT_ROLE_ID`/`VAULT_SECRET_ID`) — см. `secrets-and-env.md` |
| Vault KV | корп-Vault | runtime-секреты сервисов, vault-agent рендерит на VPS |

- SSH-**ключ** лежит на машине (`~/.ssh/…`); в файле — только **куда** ходить (host/port/user).
  **Host берётся из `.env.local`, ничего не хардкодим** в скриптах.
- Живёт в корне, в `.gitignore` (покрыт `.env.*` + `*.local`). Committed только `.env.local.example`
  (плейсхолдеры + откуда брать). В авто-backup'ы не уезжает — копия у оператора (Vaultwarden).
- **Формат:** dotenv, `KEY=value` на строку. Парсится `grep`'ом, **не** `source`'ом — без
  многострочных значений, `$`-подстановок, inline-команд.

## Поведение: токен из чата → в `.env.local`

Когда оператор присылает токен/креду в чат — агент **записывает её в `.env.local`** (Write/Edit) под
понятным ключом и **не повторяет значение** в ответе. Подтверждает фактом («записал `<KEY>` в
`.env.local`»), не цитируя секрет. Это канон этого репо.

## Security-инвариант

- **Доступ к значению — только через tools.** `scripts/tools/ssh.sh` сам `grep`-ает `KEY=` из
  `.env.local` и использует значение внутри bash-процесса — в stdout/transcript оно не попадает.
- ❌ **`Read`/`cat`/echo ради значения креда — необратимая утечка** в transcript: придётся
  ротировать. Нужен токен — зови tool, не вытаскивай значение в чат.
- ❌ Эхоить `VAULT_SECRET_ID`/`ROLE_ID`, deploy-key, токены при онбординге/bootstrap (skill
  `bootstrap-vps`/`request-secret`): подтверждай факт, не печатай значение.
- ❌ Коммитить `.env.local` (gitignore страхует, но `git add -A` цепляет — проверяй `git status`).
- ❌ Класть сюда долгоживущие runtime-секреты приложения (их место — Vault) или серверный `.env`.

## Известные ключи

| Ключ | Используется | Примечание |
|---|---|---|
| `SSH_HOST` / `SSH_PORT` / `SSH_USER` | `scripts/tools/ssh.sh` (ops-вербы, `make ssh`, серверный смок `make status`) | куда ходить; ключ — на машине |
| `HOST` | `ssh.sh` (override `user@ip`) | разовая сессия на другой хост |
| `PROJECT_NAME` | `ssh.sh` (`REMOTE_DIR=/opt/<p>-infra`) | имя проекта на VPS |
| `<TOKEN>` | по мере необходимости | токены, присланные оператором (registry/API/…) |
