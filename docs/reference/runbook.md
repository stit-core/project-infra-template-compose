# Runbook

Common failure modes на проектном VPS и что делать. Ordered by likelihood.

## Сервис падает на пустых секретах

**Симптом:** postgres/backend/minio в restart-loop сразу после старта, в логах — пустой пароль / невалидный DSN / auth failed.

Возможные причины:
- **Секция профиля не заполнена в `.env`** — профиль включён в `COMPOSE_PROFILES`, а его переменные (см. `.env.example`) пустые. Возьми набор переменных профиля из `.env.example`, заполни в `.env`, `make deploy`.
- **Контейнер создан до заполнения `.env`** — environment фиксируется при container CREATE. `make deploy` пересоздаст сам; точечно — `make recreate SVC=<svc>`.
- **Опечатка в имени переменной** — `make doctor` (секция `.env coverage`) покажет незаполненные ключи из `.env.example`.

## Backend в restart-loop

```bash
docker logs backend --tail=100
```

- **PG_DSN ошибка:** проверь `POSTGRES_*` в `.env` на VPS (PG_DSN собирается интерполяцией в `compose/backend.yml`). Пустой пароль → заполни секцию profile postgres и `make deploy`.

## Traefik не выдаёт LE-cert

**Симптом:** `curl https://api.<DOMAIN>` отдаёт SELF_SIGNED или TIMEOUT, в логах traefik — `unable to obtain ACME certificate`.

```bash
docker logs traefik --tail=200 | grep -i 'acme\|challenge'
```

Чек-лист:
- A-record на `api.<DOMAIN>` указывает на IP VPS? `dig +short api.<DOMAIN>`.
- Порт 80 открыт извне? HTTP-01 challenge ходит на `:80/.well-known/acme-challenge/...`.
- Rate limit LE: 50 cert/week per registered domain. Если хитанули — ждать неделю или использовать staging endpoint (отдельный `caServer` в traefik.yml).
- `/letsencrypt/acme.json` существует и `chmod 0600`? Иногда после восстановления volume'а права слетают.

## Edge отвечает 404 на всех адресах после рестарта Traefik

**Симптом:** после рестарта Traefik (деплой с правкой `configs/traefik/`, `make restart SVC=traefik`, перезагрузка хоста) все адреса отвечают `404 page not found`, а `make ps` показывает `traefik` healthy.

Плагин bouncer CrowdSec Traefik качает из сети при каждом старте. Сбой загрузки выключает плагины, и роутеры с `crowdsec@file` — то есть все — не собираются:

```bash
docker logs traefik 2>&1 | grep -i plugin   # «Plugins loaded» — норма, «Plugins are disabled» — сбой загрузки
make restart SVC=traefik                     # повторить загрузку
```

`make deploy` сверяет строку `Plugins loaded` сам: при сбое рестартует Traefik до двух раз, а если не помогло — отказывает с `ERR: traefik: плагин bouncer не загружен`; тогда проверь выход VPS в сеть (`plugins.traefik.io`). После рестарта вне деплоя — `make restart`, перезагрузка хоста — сверяй ту же строку лога сам.

## Журнал доступа Traefik

`/var/log/traefik/access.log` на хосте: JSON-строка на каждый ответ, с `request_User-Agent` и `X-Request-Id`. Его читает CrowdSec. Ротация — расписание стека (`configs/crowdsec/crontab`, crond в контейнере `crowdsec`): раз в сутки и вне очереди, когда файл перерос 256 МиБ; копии — `access.log.1.gz` (свежая) … `access.log.14.gz`.

- **Журнал растёт, копий нет:** `docker exec crowdsec crontab -l` — расписание на месте? `docker exec crowdsec pgrep crond` — crond жив? Нет — `make restart SVC=crowdsec`. Ротация руками — `docker exec crowdsec sh /opt/edge/rotate-access-log.sh`.
- **Правка расписания** — `configs/crowdsec/crontab`, затем `make ship`: деплой рестартует `crowdsec`, crontab ставится на старте контейнера.

## Postgres dead / data lost / wrong migration

Backup-формат — `pg_dumpall | gzip | restic backup --stdin` (один файл `pgdump-<UTC>.sql.gz` внутри snapshot'а, не tree).

**Не делай `restic restore --target /data`** — снапшоты не содержат volume-структуру, restore не вернёт раздел `postgres-data`. Только через `restic dump <id> <filename> | gunzip | psql`.

Канон — helper-скрипт. На VPS из `/opt/<p>-infra/`:

```bash
docker exec backup restic snapshots --compact        # выбрать ID или latest
make restore-pg SNAPSHOT=latest                       # либо SNAPSHOT=<id>
```

Что делает (см. `scripts/restore-pg.sh`):
1. Resolve dump-файла внутри snapshot'а (`/pgdump-<UTC>.sql.gz`).
2. Печатает план и спрашивает `y/N`.
3. Stop backend (если в стеке).
4. `DROP DATABASE $POSTGRES_DB`.
5. `restic dump | gunzip | psql -d template1` — pg_dumpall script сам CREATE'ит DB + `\connect` + загружает данные.
6. Start backend.

Если postgres сам не стартует (corrupted volume, incompatible server version):

```bash
docker logs postgres --tail=100
# Если действительно volume corrupted и есть свежий snapshot:
docker compose <args> stop postgres
docker volume rm <project>_postgres-data    # !!! только когда volume точно потерян
docker compose <args> up -d postgres        # стартует чистый
make restore-pg SNAPSHOT=latest             # подтягивает данные из snapshot'а
```

## Restic backup не идёт

```bash
docker exec backup restic snapshots
docker exec backup restic check
```

- **`Fatal: unable to open repo`**: `RESTIC_PASSWORD` / S3-креды / `RESTIC_REPOSITORY` ротированы. Меняются в `.env` на VPS, после — `make deploy` (compose пересоздаст backup сам) или точечно `make recreate SVC=backup` (environment подхватывается только при CREATE, не restart).
- **Cron не триггерит**: cron внутри контейнера, не на хосте. Проверь `docker exec backup pgrep crond` и `docker logs backup --tail 20`. Если crond упал — `make restart SVC=backup`. Расписание — `containers/backup/crontab`, rebuild при изменении.
- **Disk full на VPS**: `df -h`. Restic-cache в `/root/.cache/restic` внутри backup-контейнера может расти — `docker exec backup restic cache --cleanup`.

## Rollback после плохого деплоя

Backend rollback (image tag):

```bash
make bump SVC=backend TAG=v0.1.0   # с workstation (проксируется на VPS) или на VPS
```

`BACKEND_TAG` живёт строго в `.env` на VPS (конвенция `<SVC>_TAG`). `make bump` правит его и делает force-recreate — rollback это тот же bump на старый тег. Неудавшийся bump откатывается сам: образ не найден или не стал healthy за 90 с — верб возвращает прежний тег в `.env`, поднимает сервис на нём и выходит с ошибкой; у первого тега сервиса прежнего нет — он остаётся в `.env`.

Infra rollback (compose/configs):

```bash
git log --oneline -10
git revert <bad-sha>
make ship
```

## Полная замена VPS

**Предусловие:** `RESTIC_REPOSITORY` указывал на **внешний** S3 (не на проектный minio — он умер вместе с хостом) и у оператора есть offsite-копия `.env` (минимум `RESTIC_*` + `BACKUP_AWS_*`). Если стоял local minio — снапшоты уже потеряны вместе с host'ом, restore невозможен.

1. Заказать новый VPS, обновить A-record `${DOMAIN}` и сабдомены на новый IP (TTL заранее снизить).
2. `ansible-playbook -i inventory.ini bootstrap.yml` (с обновлённым `ansible_host`). Зарегистрировать deploy-key.
3. На новом VPS: `make new-env` + восстановить секреты в `.env` из offsite-копии (`RESTIC_*`, `BACKUP_AWS_*`, секции активных профилей).
4. `make ship` (или на VPS `make deploy`) → стек поднимается, postgres стартует пустой.
5. Restore postgres из restic:
   ```bash
   docker exec backup restic snapshots --compact   # выбрать snapshot
   make restore-pg SNAPSHOT=latest
   ```
6. Сверь новый IP во внешних системах, которые на него завязаны (webhook'и, allowlist'ы).
7. App-uploads (minio-data) — не покрыто backup'ом. Если настроен external mirror (`mc mirror`) — оттуда; если нет — данные потеряны.

## Quarterly DR drill

Backup, который ни разу не тестировался, не работает. Раз в квартал:

1. Поднять throwaway-инстанс postgres локально (или на staging VPS): `docker run --rm -d --name pg-drill -e POSTGRES_PASSWORD=drill postgres:17.9-alpine`.
2. Снять последний dump из restic в файл:
   ```bash
   docker exec backup restic ls latest                              # имя файла
   docker exec backup restic dump latest /pgdump-<UTC>.sql.gz \
     | gunzip > /tmp/drill.sql
   ```
3. Загрузить в throwaway: `docker exec -i pg-drill psql -U postgres < /tmp/drill.sql`.
4. Sanity-checks: `\dt` показывает таблицы, `SELECT count(*) FROM <main_table>` адекватен.
5. Записать результат + дату в `docs/incidents/YYYY-MM-DD-dr-drill.md` (создать папку если нет).
6. `docker rm -f pg-drill` + `rm /tmp/drill.sql`.

Если хотя бы один шаг сломался — это инцидент сам по себе. Чини backup-флоу до следующего prod-инцидента.

## Docker Engine старше 25

**Симптом:** `make deploy` / `make bump SVC=site` не создаёт контейнер `site` — compose отвергает `healthcheck.start_interval` (`compose/site.yml`); плагин compose до v2.20.2 не разбирает сам файл, и падает любой верб, даже без профиля `site`.

`make doctor` называет версию строкой `docker engine`: FAIL при профиле `site`, иначе WARN. Роль `ansible/roles/docker` ставит свежий движок на новый VPS и не обновляет уже установленный — на действующем VPS:

```bash
apt-get update && apt-get install --only-upgrade docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

Обновление пакета рестартует docker-демон — контейнеры стека перезапускаются. После него — `make doctor` и `make ps`.

## Не-прод среда сайта: замок и индексация

- **Порядок включения.** Сначала `make deploy` с `STAGING_BASIC_AUTH_USERS` в `.env`, потом `make bump SVC=site` с содержимым, которое должно быть закрыто. Замок встаёт пересозданием контейнера сайта: запросы, начатые в долю секунды между остановкой прежнего контейнера и снятием его роутеров, ещё проходят по прежней цепочке — без пароля.
- **`make deploy` отказывает с `ENV-ERR: STAGING_BASIC_AUTH_USERS`** — значение не `'user:hash'` в одинарных кавычках, логин вне `A-Za-z0-9._@-` или хеш не bcrypt целиком: `htpasswd -nbB <user> '<пароль>'` (`.env.example § profile site`). Стек при отказе не тронут — прежний замок действует.
- **Прод-среда отвечает `X-Robots-Tag: noindex`.** `make new-env` открывает индексацию только при `ENV=prod` буквально; прод-среде с другим именем (`production`, `PROD`) `ROBOTS_POLICY=index` в `.env` ставит оператор, затем `make deploy`.
- **`make deploy` отказывает с `ENV-ERR: DOMAIN`** — при профиле `site` домен обязан быть записью хоста: строчные буквы, IDN — в punycode, без схемы, порта, пути и точки на конце. Сайт получает его как `SITE_URL` и с другой записью не стартует.

## Образ сервиса не пуллится из registry

**Симптом:** `make bump` / `make deploy` падает на pull — `manifest unknown` или `unauthorized`.

- **`manifest unknown`** — такого тега нет в registry: образ выпускает `/release` сервис-репо;
  сверь тег с его релизом и повтори `make bump SVC=<svc> TAG=<tag>`.
- **`unauthorized`** — VPS не залогинен в registry: оператор делает на VPS `docker login
  <REGISTRY_HOST>` с PAT из Gitea (`docs/getting-started.md`, шаг 3).
- **Путь образа** — `${REGISTRY_HOST:-git.stit.tech}/${PROJECT_NAME}/<svc>`: `PROJECT_NAME` в `.env`
  должен совпадать с org, куда сервис-репо пушит образ (`docs/reference/ecosystem.md`).
