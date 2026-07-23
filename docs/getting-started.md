# Getting started — от шаблона к своей проектной VPS

**[META]** Этот файл — для потребителя шаблона. Описывает путь от форка до проекта, который
ничего не помнит про шаблон. Удаляется на шаге де-темплейтизации (`/de-template`).

Принцип: **поднимите платформу скриптами, спроектируйте проект скиллами — не правьте фундамент
руками.** Multi-env: один проект имеет N сред (`dev`, `prod`, ...) — **N отдельных VPS**, по
одному на `ENV`. Шаги 1–8 проходите на каждый VPS отдельно (корп-handoff —
один раз, шаг 1).

**Два пути control-plane.** Корп control-plane (registry) — это либо **managed**
stit (`git.stit.tech`; корп-шаги на шаге 1 делает stit), либо **self-hosted** — ваш форк
`corp-infra-template` на своём VPS (корп-шаги делаете вы на нём). Куда смотрит проектная VPS,
задаётся в `.env` через `REGISTRY_HOST`
(managed-дефолт в `.env.example`). Вендор-лока нет — архитектура та же, меняется только хост.

**Где вы работаете.** Репо живёт на **рабочей станции оператора** — здесь authoring / validate /
plan / ship. Живого стека локально нет: приложения и контейнеры крутятся на удалённом VPS (один
VPS = одна среда). `make ship` пушит и триггерит remote `deploy.sh` по SSH; ops-вербы (`make ps`/
`logs`/`restart`) ходят на VPS через `scripts/tools/ssh.sh` (connection из `.env.local`,
fallback `ansible/inventory.ini`).
Локальный SKIP authoring-проверок без `.env`/docker — норма, не падение.

## Pre-requisites

- Куплены VPS (Debian 12 / Ubuntu 24.04, 2–4 GB RAM, 40+ GB disk) — по одному на env.
- Для каждого env опубликован домен с A-записью на IP соответствующего VPS (LE HTTP-01).
  Convention — `<env>.<domain>` или `<env>-<domain>`, но это вне шаблона.
- Доступ к корп control-plane: на managed — выданный stit; на self-hosted —
  Gitea admin вашего форка `corp-infra-template`.
- Локально: ansible 2.15+, git, ssh.

## 0. Форк

1. Gitea (`https://git.stit.tech`) → `stit-core/project-infra-template-compose` →
   **Use this template** → `<org>/infra`.
2. `git clone git@git.stit.tech:<org>/infra.git && cd infra`.
3. `make setup` — ставит git-хуки (commit-msg, pre-commit на `roadmap.md` + `docs/project/`).

На self-hosted замените `git.stit.tech` на git вашего control-plane (`REGISTRY_HOST`).

## 1. Day-0 — корп-handoff (один раз на все env)

Корп-стороне нужно от проекта две вещи (**managed:** делает stit по запросу;
**self-hosted:** делаете вы на своём форке `corp-infra-template`):

- **Registry-доступ** к `git.stit.tech` — pull для VPS + push для разработчика
  backend-форка (Gitea-аккаунт/PAT).
- **CrowdSec-whitelist** egress-IP каждой проектной VPS — иначе служебный трафик
  к корп-сервисам режется 403 (`configs/crowdsec/whitelists.yaml` corp-side +
  restart crowdsec).

Секреты проекта корп не выдаёт — они целиком в `.env` на VPS (шаги 4 и 6).
Подробности контракта — `.claude/rules/multi-env.md`.

## 2. Day-1 — bootstrap чистого VPS

Канон — skill `/bootstrap-vps` (ведёт весь шаг). Под капотом:

```bash
ansible-galaxy collection install -r ansible/requirements.yml   # один раз: ansible.posix
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

Из вывода ansible скопируйте pubkey → `<org>/infra` → Settings → Deploy Keys (read-only).
Перезапустите clone:

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard
```

Логин в registry на VPS (PAT из Gitea → Settings → Applications; на self-hosted — git вашего
control-plane):

```bash
ssh root@<vps> 'docker login git.stit.tech -u <user> -p <PAT>'
```

## 4. Заполнить `.env` на VPS

```bash
ssh root@<vps>
cd /opt/<project>-infra
PROJECT_NAME=acme ENV=prod DOMAIN=acme.com ACME_EMAIL=ops@acme.com \
make new-env
```

Создаёт `.env` (chmod 600) — identity + ACME. Секреты профилей дописываются по
необходимости (шаг 6). `CROWDSEC_BOUNCER_API_KEY` заполняется автоматически на
первом деплое. На self-hosted допишите в `.env` адрес своего registry
(`REGISTRY_HOST` — см. `.env.example`). Строка
`# COMPOSE_PROFILES=` закомментирована — раскомментируете по мере активации сервисов.

## 5. Первый деплой — минимальный стек

С рабочей станции оператора:

```bash
make ship          # commit + check + push + (на main) ssh-deploy
```

Или на VPS с пошаговым stdout: `make deploy`. Что произойдёт:
1. `render-configs.sh` — envsubst для traefik.yml / middlewares / landing из `.env`.
2. Always-on (traefik / crowdsec / node-exporter / cadvisor / landing) стартуют.
3. Traefik запрашивает LE-cert на `${DOMAIN}` (landing).
4. CrowdSec bouncer auto-register на первом подъёме — заполняет `CROWDSEC_BOUNCER_API_KEY`.

Проверка: `make ps` (все healthy), `curl -fsS https://${DOMAIN}/` (landing через traefik+LE).

## 6. Активация дополнительных профилей

По мере того как нужны postgres / storage / backend — заполняете секреты и активируете profile.

1. Skill `/request-secret` — определит набор переменных профиля (контракт —
   `.env.example`), сгенерит случайные значения где нужно (`openssl rand`).
   Печатает блок `VAR=value` — допишите его в `.env` на VPS.
2. Там же в `.env` отредактируйте:
   ```
   COMPOSE_PROFILES=postgres,storage,backend
   ```
   (`storage` обязательно с `postgres` — backup делает pg_dumpall; deploy.sh валидирует.)
3. `make ship` (без MSG, чистое дерево → push + deploy). Compose сам пересоздаёт
   сервисы, чей environment изменился.

Какой профиль какие переменные требует — `.claude/rules/multi-env.md § Profile-based opt-in`.

## 7. `/init-project` — спроектировать инфру под продукт

Skill-оркестратор `/init-project` ведёт онбординг инфры: читает продуктовый контекст из соседнего
`<org>/strategy` (vision / surface продукта `docs/projects/<slug>/` — форк `business-strategy-template`, sibling-checkout) → проектирование
стека и **карты сервисов** (`/stack-deep-dive`) → hosted-сервисы (`/service-deep-dive`) →
`/de-template`. Сам не проектирует — чейнит специализированные скиллы и наполняет `docs/project/*`
(`stack.md` + `services/<name>.md`) до `status: stable`, затем чейнит развёртку.

Продуктовый слой (vision / surface) **не авторится здесь** — он живёт в `<org>/strategy` (продукт
в `docs/projects/<slug>/`) и проектируется его скиллами. Этот шаг читает его как scope. Резолв пути — `docs/reference/ecosystem.md`.

## 8. `/de-template` — своя инфра

`/de-template` читает stable-артефакты `docs/project/`, мутирует репо in-repo: прунит
неиспользуемые `compose/*.yml` + секции `.env.example`, ставит
`COMPOSE_PROFILES`, кастомит `CLAUDE.md`/README под идентичность проекта, срезает scaffolding.
Cross-repo (форки backend/frontend, заполнение `.env` на VPS) — печатает next-steps, не выполняет.

## Готово

Проект больше ничего не помнит про шаблон: свой домен, свой набор профилей, свой `CLAUDE.md`.
Дальше — обычный дневной флоу через `/smartdev` (устройство `.claude`-слоя — `docs/contributing.md`).
Когда что-то сломалось — `docs/reference/runbook.md`.
