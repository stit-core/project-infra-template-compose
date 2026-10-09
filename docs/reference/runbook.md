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

## Traefik перезапускается, edge не отвечает

**Симптом:** после рестарта Traefik (деплой с правкой `configs/traefik/`, `make restart SVC=traefik`, перезагрузка хоста) соединения на 80 и 443 отклоняются, `make ps` показывает `traefik` в состоянии `restarting`, `make deploy` отказывает с `container traefik is unhealthy`.

Плагин bouncer CrowdSec Traefik качает из сети при каждом старте и без него не стартует (`experimental.abortOnPluginFailure` в static-конфиге): с выключенными плагинами роутеры с `crowdsec@file` — то есть все — не собрались бы, и edge отвечал бы 404 при `healthy`.

```bash
docker logs traefik --tail=5   # «unable to install plugin crowdsec-bouncer» — нет выхода к plugins.traefik.io
```

Лечится само: политика `restart` повторяет старт (пауза между попытками растёт до минуты), и Traefik поднимается, как только VPS видит сеть. Проверь выход VPS в сеть; после — `make deploy` или `make ps`.

## Edge отвечает 429 на всех адресах

**Симптом:** любой адрес отвечает `429`, и новому клиенту тоже; `make ps` — `crowdsec` не healthy или перезапускается.

Bouncer Traefik спрашивает решение у LAPI CrowdSec на каждый новый адрес клиента (вердикт держит в кеше до 60 с) и, пока LAPI не отвечает, отказывает — 429. Поэтому `crowdsec` здоров, только когда LAPI отвечает, и Traefik стартует после него.

- `docker logs crowdsec 2>&1 | grep 'Local API listening'` — строка есть? Нет — LAPI ещё не поднялся: первый старт ставит коллекции из хаба CrowdSec — до минуты, нужен выход в сеть. Хвост лога (`--tail`) занят строками LAPI — он пишет каждую пробу здоровья и каждый вопрос bouncer о новом адресе клиента; нужное ищут через `grep`: `level=error`, `crond:`, `bots-allowlist`, `rotate-access-log`.
- Рестарт и пересоздание `crowdsec` (`make restart SVC=crowdsec`, деплой с правкой `compose/crowdsec.yml`, `configs/crowdsec/acquis.yaml` или `crontab`) — 6–8 секунд отказа 429 клиентам без вердикта в кеше: без нужды его не рестартуют.
- 429 одному адресу, а не всем — решение о бане: `docker exec crowdsec cscli decisions list`; снять — `docker exec crowdsec cscli decisions delete --ip <адрес>`.
- Источник журнала пуст (`docker exec crowdsec cscli metrics show acquisition` — нет строки `file:/var/log/traefik/access.log`) — сценарии не работают: сверь `configs/crowdsec/acquis.yaml` и каталог `/var/log/traefik` на хосте, затем `make restart SVC=crowdsec`.

## Allowlist ботов в CrowdSec

Кого `robots.txt` сайта пускает, того edge не банит: у каждого бота из `configs/crowdsec/ai-bots.sources` с адресом списка сетей вендора — свой allowlist `bot-<токен>`. Обновляет задание `configs/crowdsec/bots-allowlist.sh`: расписание стека раз в неделю, `make allowlist` (все списки), `make deploy` (только недостающие и не обновлявшиеся дольше шести дней). У попытки загрузки списка срок — 30 с, попыток — до четырёх; у задания целиком — 600 с.

```bash
docker exec crowdsec cscli allowlists list          # allowlist bot-…: адрес источника, дата обновления, число сетей
docker exec crowdsec cscli allowlists check <адрес>  # в каком allowlist адрес
make allowlist                                        # обновить все списки сейчас
```

- **`WARN <бот>: источник не ответил или не дал ни одной сети`** — источник недоступен, отдал не список или четыре попытки не уложились в срок; прежний allowlist бота остаётся (записи живут 21 день); повтори `make allowlist`. Источник не отвечает неделями или сменил формат — задача репо сайта: адрес списка живёт в его реестре ботов.
- **`WARN <бот>: список не принят — <причина>`** — ответ вендора вышел за пределы задания: больше 4096 сетей одного семейства, охват шире 262 144 адресов IPv4 или 65 536 сетей `/64` IPv6, либо в списке не публичные адреса (частные, loopback, link-local, зарезервированные). Список не принят целиком, прежний allowlist бота остаётся (записи живут 21 день). Пределы — константы `MAX_*` в шапке задания: вендор и правда вырос — правка констант коммитом; сети не те — задача репо сайта, адрес списка живёт в его реестре ботов.
- **`WARN <бот>: список не принят — редирект на <адрес>`** — источник перенаправляет не на `https://`: список по `http` и другим схемам в allowlist не попадает. Редирект по `https` принимается и на другой хост — его назначает сам вендор (у Perplexity список живёт на втором домене); такие списки называет строка задания `список взят по редиректу на другой хост` — повод внести конечный адрес в реестр ботов сайта.
- **`WARN задание идёт <N> с — дольше своего срока`** (вывод `make allowlist` и `make deploy`, `ATTENTION` блока `-- edge --` в `make status`) — замок задания занят дольше его срока, и allowlist не обновляется; запуск завершается с кодом 2. `docker exec crowdsec ps` покажет, что осталось от задания; снимает `make restart SVC=crowdsec` (6–8 секунд отказа 429 клиентам без вердикта в кеше).
- **`WARN задание прервано (код <N>; срок — 600 с)`** — задание не уложилось в срок и снято вместе со своими процессами; не обновлённые списки доберёт следующий запуск — `make allowlist`.
- **`уже идёт (<N> с) — пропуск`** — задание уже запущено расписанием, деплоем или вторым `make allowlist`: не ошибка, код 0.
- **`в образе нет ssl_client`** — после бампа образа CrowdSec пропал помощник TLS, которым `wget` сверяет сертификат источника: задание отказывает (код 1), allowlist не меняется. Верни образ, в котором помощник есть (в Alpine — пакет `ssl_client`).
- **`сервис site не отвечает — allowlist не меняется`** — задание читает политику с `http://site:3000/robots.txt`: `make ps`, `make logs SVC=site`.
- **Сайт сменил политику ИИ-ботов** (строка `AI-BOTS` handoff релиза): после `make bump SVC=site` — `make allowlist`; allowlist бота, которого `robots.txt` закрыл именной группой, снимается.
- **Сменилась версия реестра ботов** (та же строка, WARN `bots sources` в `make doctor`): в хабе `make bots-sources` (нужен сосед `<org>/site` на теге релиза), затем `make ship`.
- **Свой allowlist** называй не с `bot-`: имена `bot-…` — за заданием, список с таким именем, которого нет среди нужных, оно удаляет.
- **Бот получил 429 от WAF**: `docker exec crowdsec cscli decisions list`; адреса из списка вендора там быть не должно — сверь `cscli allowlists check <адрес>` и дату обновления списка.

## Бан адреса поисковика

Поисковика без списка сетей (Яндекс; остальным — страховка к allowlist) от сценариев обхода бережёт обратная запись DNS: при переполнении сценария CrowdSec один раз спрашивает PTR адреса (постоверфлоу `rdns`) и сверяет суффикс со списком `seo-bots-whitelist`. Запрос без ответа — бан адреса поисковика на 4 часа: резолвер контейнера повторяет запрос до пяти раз (`dns_opt` в `compose/crowdsec.yml`), но пока DNS VPS не отвечает, бан состоится.

```bash
docker exec crowdsec cscli decisions list                 # адреса под баном и сценарий
dig +short -x <адрес>                                     # PTR на yandex.ru / yandex.net / yandex.com, googlebot.com, search.msn.com — поисковик
docker exec crowdsec cscli decisions delete --ip <адрес>  # снять бан
```

Баны поисковиков повторяются — проверь резолвер VPS: `dig -x <адрес>` обязан отвечать за доли секунды.

## Журнал доступа Traefik

`/var/log/traefik/access.log` на хосте: JSON-строка на каждый ответ, с `request_User-Agent` и `X-Request-Id`. Его читает CrowdSec. Ротация — расписание стека (`configs/crowdsec/crontab`, crond в контейнере `crowdsec`): раз в сутки и вне очереди, когда файл перерос 256 МиБ; копии — `access.log.1.gz` (свежая) … `access.log.14.gz`.

- **Журнал растёт, копий нет:** `docker exec crowdsec crontab -l` — расписание на месте? `docker exec crowdsec pgrep crond` — crond жив? Нет — `make restart SVC=crowdsec`. Ротация руками — `docker exec crowdsec sh /opt/edge/rotate-access-log.sh`.
- **Правка расписания** — `configs/crowdsec/crontab`, затем `make ship`: деплой рестартует `crowdsec`, crontab ставится на старте контейнера.

## Вербы отказывают с `ENV-ERR`

**Симптом:** `make deploy`, `render`, `ps`, `logs`, `restart`, `recreate`, `build`, `bump`, `restore-pg` отвечают `ENV-ERR: <ключ> — .env, строка <N>: нужна форма KEY=значение…` и ничего не делают; `make doctor` и `make validate` называют ту же строку красной проверкой.

Строка `.env` не той формы: шелл скриптов и compose прочли бы её по-разному, а в тексте своих ошибок напечатали бы кусок значения — хеш, пароль. Поэтому вербы останавливаются раньше чтения файла. Отказ дают: пробел у `=`, значение с пробелом, `$` или знаком шелла без одинарных кавычек, `export KEY=…`, подстановка `"…${VAR}…"`, комментарий или пробел после значения, перевод строки CRLF. Сам `docker compose` такие строки читает — стек, поднятый раньше, продолжает работать.

Аварию при такой строке разбирают без этих вербов:

```bash
make status                       # смок: хост, контейнеры, edge — .env не читает
docker ps                         # состояние контейнеров
docker logs <сервис> --tail=100   # лог сервиса
make doctor                       # ключ и номер каждой строки не той формы (первые пять)
```

Исправь строку по номеру — значение в одинарные кавычки, комментарий отдельной строкой — и повтори верб.

## Деплой пересоздаёт Traefik и CrowdSec

Правка их compose-файлов (образ, healthcheck, тома, `dns_opt`) пересоздаёт контейнеры edge. На стенде это 10–11 секунд без ответа сервисов: дважды отказ соединения на 2–3 секунды (пересоздание и рестарт Traefik) и 5–6 секунд 429, пока bouncer не получит вердикт у поднявшегося LAPI. Правка одного `configs/traefik/` — рестарт Traefik, секунды.

`scripts/deploy.sh`, обновлённый тем же `git pull`, продолжает новой версией сам — строка `→ scripts/deploy.sh обновлён этим pull`. `deploy.sh` без этой передачи доходит по-своему, и шаги новой версии остаются несделанными: после `make deploy` при профиле `site` нет строки `→ allowlist ботов (CrowdSec)` — запусти `make deploy` второй раз.

Перед обновлением `make doctor` назовёт строки `.env`, которые деплой отвергнет (`ENV-ERR`): `export KEY=…`, `$` без одинарных кавычек, комментарий после значения.

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
