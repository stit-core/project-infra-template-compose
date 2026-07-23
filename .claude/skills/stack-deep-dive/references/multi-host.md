# Multi-host split (opt-in) — швы проектной VPS

Дефолт — **single-host**: весь стек на одном VPS (один VPS = одна среда),
`HOST_ROLE=all`. Postgres / MinIO co-located, эндпоинты — имена контейнеров.
Ничего не меняется, пока оператор явно не выберет split.

**Split** — opt-in: Postgres / MinIO+backup / edge+app разносятся по отдельным
VPS (несколько серверов на одну среду). **Шаблон даёт ТОЛЬКО швы** (эндпоинты
бэкендов в `.env` + таргетинг compose по ролям). Cross-host сеть, TLS между
хостами, репликация/HA/failover, S3-репликация — **дело потребителя** (см. § Граница).

## Шов 1: эндпоинты бэкендов — в `.env`

Адреса PG / restic-репозитория — переменные `.env`; при split их наводят на
целевой хост, не трогая compose:

| Что | Где | single-host дефолт | split |
|---|---|---|---|
| Postgres host/port | `.env` `PG_HOST`/`PG_PORT` (опц.) | `postgres` / `5432` | db-хост |
| restic-репозиторий | `.env` `RESTIC_REPOSITORY` | MinIO на этом VPS | storage-хост / managed S3 |

`PG_DSN` собирается compose-интерполяцией `${PG_HOST:-postgres}:${PG_PORT:-5432}`
— `.env` без этих переменных даёт дефолт (single-host, байт-в-байт).

## Шов 2: `HOST_ROLE` — таргетинг compose по ролям

`HOST_ROLE` (`.env` каждого хоста) выбирает, какие compose-файлы поднимать.
`scripts/deploy.sh` держит карту `роль → набор -f`. Project name = имя
директории (хосты split физически разные VPS — коллизий томов нет, per-host
`-p` не нужен).

| Роль | compose-файлы | несёт |
|---|---|---|
| `all` | `docker-compose.yml` + все `compose/*.yml` | весь стек (single-host, дефолт) |
| `edge` | docker-compose + traefik + crowdsec + landing + backend | edge + app |
| `db` | docker-compose + postgres | Postgres |
| `storage` | docker-compose + minio + backup | MinIO + restic-backup |

`COMPOSE_PROFILES` по-прежнему гейтит postgres/storage/backend — на split-хосте
ставится профиль его роли (`db` → `COMPOSE_PROFILES=postgres`, `storage` →
`storage`). Дефолт `HOST_ROLE=all` даёт прежний `-f`-набор — рендер не меняется.

## Шов 3: per-host backup

При split backup (роль `storage`) делает `pg_dumpall` к Postgres на db-хосте
**по сети** (`PG_HOST` из `.env`). Co-location-проверка `storage ⇒ postgres` в
`deploy.sh` активна только при `HOST_ROLE=all`; при split она снята (PG на
другом хосте — норма). Cross-host доступ к PG обеспечивает потребитель.

## Граница: что шаблон НЕ делает (дело потребителя)

- **Cross-host сеть.** Docker service-name DNS работает только внутри одного
  хоста. При split backend (edge) ходит в Postgres (db) и MinIO (storage) по
  адресам из `.env` — нужна private LAN / wireguard / overlay между VPS. Шаблон
  даёт env-эндпоинты, не сетевую фабрику.
- **TLS/шифрование трафика между хостами** (PG, S3 по сети).
- **Репликация / HA / failover** (Postgres master+replica, MinIO distributed).
- **Раскладка `.env`.** Каждый хост держит свой `.env` (identity + секреты
  сервисов его роли) — раскладывает оператор.

Граница — present-state policy: split-шаблон осознанно останавливается на швах,
чтобы не навязывать конкретную HA-топологию. Дизайн раскладки `host → services`
фиксируется в `state/stack.md § Host layout`; шаг single-host vs split — в
`stack-deep-dive` (`references/field-checklists.md § Networks`).
