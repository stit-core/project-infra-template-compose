# Multi-host split (opt-in) — швы проектной VPS

Дефолт — **single-host**: весь стек на одном VPS (один VPS = одна среда),
`HOST_ROLE=all`. Postgres / MinIO co-located, эндпоинты — имена контейнеров.
Ничего не меняется, пока оператор явно не выберет split.

**Split** — opt-in: Postgres / MinIO+backup / edge+app разносятся по отдельным
VPS (несколько серверов на одну среду). **Шаблон даёт ТОЛЬКО швы** (эндпоинты
бэкендов в KV + таргетинг compose по ролям). Cross-host сеть, TLS между хостами,
репликация/HA/failover, S3-репликация — **дело потребителя** (см. § Граница).

## Шов 1: эндпоинты бэкендов — в Vault KV (не в `.env`)

Адреса PG / restic-репозитория проектная сторона берёт из KV (рендерит
vault-agent) — при split их наводят на целевой хост, не трогая compose:

| Что | Где | single-host дефолт | split |
|---|---|---|---|
| Postgres host/port | KV `kv/.../db` поля `host`/`port` (опц.) | `postgres` / `5432` | db-хост |
| restic-репозиторий | KV `kv/.../backup.repository` | MinIO на этом VPS | storage-хост / managed S3 |
| OTLP-коллектор | `.env` `OTEL_EXPORTER_OTLP_ENDPOINT` | managed `otel.stit.tech:443` | свой коллектор |

`backend.env.tpl` рендерит `PG_DSN` через `{{ or .Data.data.host "postgres" }}:{{
or .Data.data.port "5432" }}` — существующие KV `db` без `host`/`port` дают
дефолт (single-host, байт-в-байт). При split корп засевает `db.host`/`db.port`.

## Шов 2: `HOST_ROLE` — таргетинг compose по ролям

`HOST_ROLE` (`.env` каждого хоста) выбирает, какие compose-файлы поднимать.
`scripts/deploy.sh` держит карту `роль → набор -f`. Project name = имя
директории (хосты split физически разные VPS — коллизий томов нет, per-host
`-p` не нужен).

| Роль | compose-файлы | несёт |
|---|---|---|
| `all` | `docker-compose.yml` + все `compose/*.yml` | весь стек (single-host, дефолт) |
| `edge` | docker-compose + traefik + crowdsec + vault-agent + otel-agent + node-exporter + cadvisor + landing + backend | edge + app + телеметрия-агент |
| `db` | docker-compose + vault-agent + postgres | Postgres |
| `storage` | docker-compose + vault-agent + minio + backup | MinIO + restic-backup |

`vault-agent` — в каждой роли (рендерит секреты на своём хосте из KV).
`COMPOSE_PROFILES` по-прежнему гейтит postgres/storage/backend — на split-хосте
ставится профиль его роли (`db` → `COMPOSE_PROFILES=postgres`, `storage` →
`storage`). Дефолт `HOST_ROLE=all` даёт прежний `-f`-набор — рендер не меняется.

## Шов 3: per-host backup

При split backup (роль `storage`) делает `pg_dumpall` к Postgres на db-хосте
**по сети** (`db.host` из KV). Co-location-проверка `storage ⇒ postgres` в
`deploy.sh` активна только при `HOST_ROLE=all`; при split она снята (PG на
другом хосте — норма). Cross-host доступ к PG обеспечивает потребитель.

## Граница: что шаблон НЕ делает (дело потребителя)

- **Cross-host сеть.** Docker service-name DNS работает только внутри одного
  хоста. При split backend (edge) ходит в Postgres (db) и MinIO (storage) по
  адресам из KV — нужна private LAN / wireguard / overlay между VPS. Шаблон даёт
  KV-эндпоинты, не сетевую фабрику.
- **TLS/шифрование трафика между хостами** (PG, S3, OTLP по сети).
- **Репликация / HA / failover** (Postgres master+replica, MinIO distributed).
- **Cross-host vault-agent.** Каждый хост запускает свой vault-agent с той же
  AppRole-парой — оператор раскладывает `.env` (identity + AppRole) на каждый VPS.

Граница — present-state policy: split-шаблон осознанно останавливается на швах,
чтобы не навязывать конкретную HA-топологию. Дизайн раскладки `host → services`
фиксируется в `state/stack.md § Host layout`; шаг single-host vs split — в
`stack-deep-dive` (`references/field-checklists.md § Networks`).
