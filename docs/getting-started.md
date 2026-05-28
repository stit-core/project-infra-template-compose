# Getting started — от шаблона к своей проектной VPS

**[META]** Этот файл — для потребителя шаблона. Описывает путь от форка до проекта, который
ничего не помнит про шаблон. Удаляется на шаге де-темплейтизации (`/de-template`).

Принцип: **подними платформу скриптами, спроектируй проект скиллами — не правь фундамент
руками.** Multi-env: один проект имеет N сред (`dev`, `prod`, ...) — **N отдельных VPS**, по
одному на `ENV`. Шаги 1–8 проходишь на каждый VPS отдельно (corp-онбординг env'ов —
один раз, шаг 1).

**Где ты работаешь.** Репо живёт на **рабочей станции оператора** — здесь authoring / validate /
plan / ship. Живого стека локально нет: приложения и контейнеры крутятся на удалённом VPS (один
VPS = одна среда). `make ship` пушит и триггерит remote `deploy.sh` по SSH; ops-вербы (`make ps`/
`logs`/`restart`) ходят на VPS через `scripts/tools/ssh.sh` (хост из `ansible/inventory.ini`).
Локальный SKIP authoring-проверок без `.env`/docker — норма, не падение.

## Pre-requisites

- Куплены VPS (Debian 12 / Ubuntu 24.04, 2–4 GB RAM, 40+ GB disk) — по одному на env.
- Для каждого env опубликован домен с A-записью на IP соответствующего VPS (LE HTTP-01).
  Convention — `<env>.<domain>` или `<env>-<domain>`, но это вне шаблона.
- Доступ к корп-инфре stit.tech: Vault root token, Gitea admin.
- Локально: ansible 2.15+, git, ssh.

## 0. Форк

1. Gitea (`https://git.stit.tech`) → `stit-infra/project-infra-template-compose` →
   **Use this template** → `<org>/infra`.
2. `git clone git@git.stit.tech:<org>/infra.git && cd infra`.
3. `make setup` — ставит git-хуки (commit-msg, pre-commit на `roadmap.md`).

## 1. Day-0 — corp-онбординг проекта (один раз на все env)

На корп-VPS, оператор с Vault root-токеном:

```bash
ssh root@stit-corp 'cd /opt/stit-infra && \
  VAULT_TOKEN=<root> bash scripts/onboard-project.sh --name acme --envs dev,prod'
```

Создаёт per-env:
- AppRole `projects-acme-<env>` (flat — Vault не принимает слеши в `auth/approle/role/<name>`) +
  policy read-only на `kv/data/projects/acme/<env>/*` и `kv/metadata/projects/acme/<env>/*`.
- `kv/projects/acme/<env>/otel` — bearer token + accountID для `otel.stit.tech`.
- `kv/projects/acme/<env>/meta` — дефолты (`backend_tag=latest`, `acme_email`, `acme_caserver`).

Возвращает по блоку на env — **сохрани**, нужно в шаге 4:
```
=== acme / dev ===
PROJECT_NAME=acme
ENV=dev
VAULT_ROLE_ID=<id>
VAULT_SECRET_ID=<id>
```

Доп. KV (`db`/`oidc`/`jwt`/`minio`/`backup`/project-specific) на этом шаге НЕ создаются —
запросишь по мере активации сервисов (шаг 6). Подробности контракта — `.claude/rules/multi-env.md`.

## 2. Day-1 — bootstrap чистого VPS

Канон — skill `/bootstrap-vps` (ведёт весь шаг). Под капотом:

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
$EDITOR ansible/inventory.ini   # ansible_host, project_name, project_repo_url, operator_ssh_pubkey
ssh-copy-id root@<vps>           # один раз — SSH-ключ на VPS
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
```

Что делает playbook:
1. `base` — apt update, swap 2G, journald limits, sysctl tuning.
2. `ssh-hardening` — no password auth, root key-only, fail2ban на `:22`.
3. `docker` — docker-ce + compose-plugin.
4. `stit-onboard` — `/opt/<project>-infra/`, ed25519 deploy key (печатает pubkey), clone из
   `<org>/infra` (упадёт на первом запуске — нет ключа в Gitea, см. шаг 3).

## 3. Зарегистрировать deploy key + registry login

Из вывода ansible скопируй pubkey → `<org>/infra` → Settings → Deploy Keys (read-only).
Перезапусти clone:

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard
```

Логин в registry на VPS (PAT из Gitea → Settings → Applications):

```bash
ssh root@<vps> 'docker login git.stit.tech -u <user> -p <PAT>'
```

## 4. Заполнить `.env` на VPS

```bash
ssh root@<vps>
cd /opt/<project>-infra
PROJECT_NAME=acme ENV=prod DOMAIN=acme.com \
VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
make new-env
```

Создаёт `.env` (chmod 600) с 5 переменными identity+auth. Всё остальное — в Vault
(засеивается по необходимости, шаг 6). `CROWDSEC_BOUNCER_API_KEY` заполняется автоматически на
первом деплое. Строка `# COMPOSE_PROFILES=` закомментирована — раскомментируешь по мере
активации сервисов.

## 5. Первый деплой — минимальный стек

С рабочей станции оператора:

```bash
make ship          # commit + check + push + (на main) ssh-deploy
```

Или на VPS с пошаговым stdout: `make deploy`. Что произойдёт:
1. `render-configs.sh` собирает `agent.hcl` из `agent.hcl.parts/` под активный
   `COMPOSE_PROFILES` (на старте — пусто, только always-on) + envsubst для middlewares/landing.
2. vault-agent логинится по AppRole, рендерит `.runtime/{env,secrets,configs}/*` из
   `kv/projects/<p>/<env>/{meta,otel}`.
3. Always-on (traefik / crowdsec / otel-agent / node-exporter / cadvisor / landing) стартуют
   после vault-agent healthy.
4. Traefik запрашивает LE-cert на `${DOMAIN}` (landing).
5. CrowdSec bouncer auto-register на первом подъёме — заполняет `CROWDSEC_BOUNCER_API_KEY`.

Проверка: `make ps` (все healthy), `curl -fsS https://${DOMAIN}/` (landing через traefik+LE).
Стек сразу виден в корп-Grafana (`$tenant=<project>-<env>`) — otel-token уже засеян.

## 6. Активация дополнительных профилей

По мере того как нужны postgres / storage / backend — запрашиваешь seed и активируешь profile.

1. Skill `/request-secret` — спросит NAME (любой slug: `db`, `minio`, `backup`, `oidc`, `jwt`,
   `stripe-key`, ...), поля + значения; сгенерит случайные где нужно (`openssl rand`). Печатает
   `vault kv put kv/projects/<p>/<env>/<name> ...` для копи-паста. Отдай корп-админу — он выполнит.
2. После seed'а на VPS отредактируй `.env`:
   ```
   COMPOSE_PROFILES=postgres,storage,backend
   ```
   (`storage` обязательно с `postgres` — backup делает pg_dumpall; deploy.sh валидирует.)
3. `make ship` (без MSG, чистое дерево → push + deploy). При смене `COMPOSE_PROFILES` deploy.sh
   rerender'ит `agent.hcl` с новыми template-блоками, restart'ит vault-agent, force-recreate
   consumer'ов (env_file читается только при container CREATE).

Какой профиль от каких KV зависит — `.claude/rules/multi-env.md § Profile-based opt-in`.

## 7. `/init-project` — спроектировать проект

Skill-оркестратор `/init-project` ведёт продуктовый онбординг: vision → проектирование сервисов
(`/service-deep-dive`) → стек (`/stack-deep-dive`) → `/de-template`. Сам не проектирует —
интервьюирует и наполняет `docs/project/*` до `status: stable`, затем чейнит развёртку.

*(Продуктовый слой достраивается — см. roadmap Phase 8. До его появления проектирование и
де-темплейтизация — вручную по чек-листу `CLAUDE.md § Что менять при копировании`.)*

## 8. `/de-template` — своя инфра

`/de-template` читает stable-артефакты `docs/project/`, мутирует репо in-repo: прунит
неиспользуемые `compose/*.yml` + `vault-agent/agent.hcl.parts`/`templates`, ставит
`COMPOSE_PROFILES`, кастомит `CLAUDE.md`/README под идентичность проекта, срезает scaffolding.
Cross-repo (форки backend/frontend, seed секретов) — печатает next-steps, не выполняет.

## Готово

Проект больше ничего не помнит про шаблон: свой домен, свой набор профилей, свой `CLAUDE.md`.
Дальше — обычный дневной флоу через `/smartdev` (устройство `.claude`-слоя — `docs/contributing.md`).
Когда что-то сломалось — `docs/reference/runbook.md`.
