---
status: in-progress
parent: ssr-frontend-template:audit-program
blocked-by: —
---

# add-site-service — сервис `site` в шаблоне инфры: из коробки и по контракту сайта

## Цель
Фаза P7 программы `audit-program` в шаблоне инфры. Шаблон поднимает сервис `site` из коробки и выполняет контракт
сайта (`infra-handoff.md`) буквально: compose-файл и профиль сервиса, роутеры и middleware Traefik, заголовки edge,
закрытый `/_image`, журнал доступа с `User-Agent`, CrowdSec, который не режет поисковых и ИИ-ботов, смок и приёмка
первого деплоя машиной, канон экосистемы и обвязка хаба — про сайт правдой. Итог — `make bump SVC=site TAG=…`
проходит на стенде шаблона с настоящим образом сайта.

## Контекст
- **Пути.** `I` = `/home/mm/git/stit-core/project-infra-template-compose` (ветка `main`, одна пишущая рука); `R` =
  `/home/mm/git/stit-core/ssr-frontend-template` (потребитель контракта, только чтение; образ сайта — из worktree
  `M/wt-p7-site` на HEAD `R`); `M` = `/home/mm/git/stit-core/stit-ssr-audit`: прогоны — `M/p7/`, валидаторы и
  приёмка — в своих `git -C I worktree add --detach M/wt-p7-<имя>`.
- **Метод и решения владельца** — `R/.claude/plans/audit-program.md`: этап → исполнитель → независимый валидатор →
  фиксы → перепроверка, шаг — коммит, план — тем же коммитом; R16, R17, R18, R01. `make ship` в фазе не используется
  (он пушит и деплоит): коммит — `git commit`, push — после закрытия фазы.
- **Контракт.** `R/docs/reference/infra-handoff.md` § 1.1–1.7 (на `c1192e7` § 1.1–1.3 повторяют `I` на `e5de963`);
  рядом — `observability.md § Боты в access-log`, скилл `/release` (строка `AI-BOTS`), реестр
  `src/shared/seo/crawlers.yaml` (sha256 `1ca0e662f76d…`, политика HEAD — `allow-all`) и его печать
  `pnpm bots:sources`.
- **Покрытие** — `M/plans/add-site-service.coverage.md`: контракт пункт за пунктом (§ 1), находки аудита (§ 2),
  расхождения с контрактом (§ 3), набор поломок приёмки (§ 4), grep-список прозы (§ 5), факты проб образов (§ 7).
  Находки — `M/reports/` (`harness`, `geo`, `security`, `contract`, `seo`); валидатор этапа A —
  `M/validation-add-site-service-A.md`.
- **Обвязка I.** `CLAUDE.md` (make-first; static-конфиг Traefik — «сначала спросить» и отдельным коммитом),
  `.claude/rules/*`, скилл `/plan`, гейт `make check`; Conventional Commits, subject ≤ 72, по-русски, трейлер
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Стенд** — одноразовый «VPS в контейнере», `M/p7/stand.sh` (команды — в шапке): контейнер `p7-vps` (`docker:dind`,
  без проброса портов) с клоном `I` в `/opt/p7-infra`, registry `127.0.0.1:5000` и `.env` от `make new-env`
  (`DOMAIN=p7.test`); `sync` везёт рабочее дерево как на VPS — через `git pull` из `make deploy`. «На стенде `X`» =
  `M/exclusive.sh M/p7/stand.sh sh 'X'`; `scurl` = `curl -sk --resolve p7.test:443:127.0.0.1` там же. Адрес клиента
  стенда частный: баны показываются строками журнала с публичным `ClientHost` и `cscli decisions list`, ответ
  bouncer — решением на адрес клиента. Теги registry: `<тег>` = `v1.0.0` (HEAD `R`), `<битый>` = `v1.0.1-broken`
  (без `/healthz`), `<asdt>` = `v1.0.2-asdt` (`allow-search-deny-training`).
- **Гейт шага:** до коммита — `make check` → `✓ check clean` и проверка шага на стенде с рабочим деревом (`sync`).
  **Гейт этапа:** проверки шагов этапа и регресс прошлых этапов на свежем стенде с нуля (`up <последний коммит>`,
  первый `make deploy`) — исполнитель и, независимо, валидатор: `M/p7/stage-a.sh`, `M/p7/stage-b.sh`.

## Не входит
- Живой VPS и домен: сертификаты Let's Encrypt (apex и `www`), DNS-записи, pull из registry с PAT, ansible-bootstrap,
  баны настоящих адресов, TTFB из сети, `/seo-audit` по прод-домену (§ 1.7 п. 10) — приёмка первого деплоя проекта.
- Правки `R` и текста контракта: расхождения — § 3 файла покрытия, их возвращает в репо сайта дирижёр. Задания
  разделов 2–3 контракта (`spa-frontend-template`, `stit-public`).
- Compose-фрагменты SPA и бота; вторая поверхность сайта на том же VPS (её заводит `/add-service` по варианту S9).
- Локальная rDNS-страховка `seo-bots-local.yaml` (§ 1.5, опция), AppSec CrowdSec, CDN перед Traefik, капча.
- Хвосты обвязки `I` вне темы сайта — строками в `backlog.md` (раздел «Handoff»).

## Критерии приёмки
- [x] **AC1** — `make bump SVC=site` проходит на стенде шаблона (критерий фазы программы): на чистом стенде при
  профиле `site` и заполненной секции `.env` выкатка образа сайта из registry даёт здоровый сервис со штамповкой
  origin; образ, который не становится healthy, и тег без образа — отказ верба; возврат на рабочий тег — снова healthy.
  Проверка: на стенде `make bump SVC=site TAG=<тег>` → код 0, `make ps` → `site` healthy, `make logs SVC=site` →
  `[entrypoint] stamped https://__site_origin__ -> https://p7.test`; `TAG=<битый>` и тег без образа → код ≠ 0
  - Подтверждено: гейт этапа (`M/p7/stage-a-s3.log`): код 0 за 6 с, healthy, штамповка; `<битый>` и тег без образа —
    код 2, прежний тег и сервис возвращены
- [ ] **AC2** — Edge отдаёт сайт одной формой адреса и только своим методам и хосту: `/` — 200; адрес без страницы —
  404; `http://` — один 301/308 на `https://`; `www` — один 301 на apex; `/index.html`, `<страница>/index.html` и
  `<страница>/` — один 301 на канон; `%2F` в пути — 404; `//<страница>` — 200 с canonical на канон; `/_image`,
  `//_image`, `/./_image`, `/%5Fimage` — 403 на edge; `POST /` и `TRACE /` — не 200; запрос с чужим `Host` до сервиса
  не доходит; порт контейнера не опубликован. Проверка: на стенде `make accept SVC=site` → разделы адреса и методов
  без ✗; 23 строки матрицы формы адреса `M/p3c/edge-contract.mjs` через edge стенда (TLS и `Host` стенда — вариант
  скрипта в `M/p7/`) → расхождений 0; `docker port site` → пусто
- [x] **AC3** — Заголовки безопасности — один список § 1.3: от edge — `Strict-Transport-Security: max-age=31536000;
  includeSubDomains`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`,
  `Permissions-Policy: camera=(), microphone=(), geolocation=()`; от приложения — `Content-Security-Policy` с
  `frame-ancestors 'none'`; `X-Frame-Options` и `X-XSS-Protection` не ставит никто; HTML сжат. Состав общий — те же
  заголовки edge у ответа заглушки. Проверка: на стенде `scurl -o /dev/null -D - -H 'Accept-Encoding: br'
  https://p7.test/` → пять заголовков и `content-encoding: br`, двух лишних нет; `scurl -o /dev/null -D - -X POST
  https://p7.test/` (отвечает заглушка) → четыре заголовка edge
  - Подтверждено: гейт этапа (`stage-a-s3.log`): пять заголовков и `br`, лишних нет; `POST /` — 405 заглушки, четыре
    заголовка edge
- [x] **AC4** — Избыточный трафик получает 429, а не 403: серия POST на `/api/contact` упирается в лимит формы, и
  заявка сверх лимита до процесса не доходит; тело формы больше 64 КиБ без `Content-Length` — 413 от edge; отказ WAF
  (решение CrowdSec о бане) — тоже 429; у лимитов нет `sourceCriterion`, в цепочке формы нет `retry` и `compress`.
  Проверка: на стенде 8 POST с `Origin: https://p7.test` и незаполненной формой → пять ответов формы (200), затем
  429, ни одного 403 и 303; вне серии chunked-тело 70 КБ → 413; `cscli decisions add --ip <адрес клиента>` → через
  ≤ 60 с `/` — 429, после `decisions delete` — 200
  - Подтверждено: гейт этапа (`stage-a-s3.log`): серия — `200` × 5, `429` × 3, до процесса дошло 5; chunked 70 КБ —
    413, до процесса 0; решение на адрес клиента — 429 в пределах 60 с, после `decisions delete` — 200
- [x] **AC5** — Не-прод закрыт тремя контурами и включается ключами `.env`: при `ROBOTS_POLICY=noindex` и замке
  `STAGING_BASIC_AUTH_USERS` `/` без пароля — 401 с `X-Robots-Tag: noindex, nofollow, noarchive`, с паролем — 200 с
  тем же заголовком, `robots.txt` сервиса — `Disallow: /`; ни одна запись `Host` не отдаёт страницу без пароля; при
  пустом замке ни его, ни заголовка edge нет; хеш замка в git не попадает; замок, который `basicAuth` не разберёт, —
  отказ до деплоя. Проверка: стенд в не-прод профиле — `scurl -I https://p7.test/` → 401 и заголовок, `scurl -u
  <пользователь>:<пароль>` → 200; `curl -H 'Host: www.p7.test:443' https://www.p7.test/<страница>` → 301;
  `git status --short` после `make render` → чисто; замок без `:` → `make deploy` — код ≠ 0 до `compose up`;
  прод-профиль → 200 без `X-Robots-Tag`
  - Подтверждено: гейт этапа (`M/p7/stage-a-s3.log`): без пароля — 401 с `X-Robots-Tag`, с паролем — 200 с ним же;
    записи `Host` — страниц сайта 0; смена пароля — без рестарта Traefik; битый замок — отказ `doctor` и `deploy`
- [ ] **AC6** — Журнал доступа полон и читается: каждая запись, и 2xx, — JSON-строка в `/var/log/traefik/access.log`
  с `request_User-Agent`; `X-Request-Id` ответа on-demand маршрута есть и в записи журнала, и в строке лога сайта;
  CrowdSec читает журнал с первого деплоя; ротация идёт в стеке без действий оператора и чтения не рвёт. Проверка: на
  стенде `scurl -A 'Mozilla/5.0 (compatible; OAI-SearchBot/1.0)' https://p7.test/` → `tail -1
  /var/log/traefik/access.log | jq '.DownstreamStatus, ."request_User-Agent"'` → 200 и UA; `docker exec crowdsec cscli
  metrics show acquisition` сразу после первого `make deploy` → строк источника > 0; после ротации активный файл
  сброшен, новая запись читается
- [ ] **AC7** — CrowdSec не режет тех, кого пускает сайт: поисковики — постоверфлоу `rdns` и `seo-bots-whitelist`;
  ИИ-боты — allowlist сетей вендоров по `ai-bots.sources` и политике `robots.txt` сервиса: при `allow-all` — сети
  всех строк с `ip_list_url`, включая обучающих; бот, закрытый именной группой, после обновления в allowlist
  отсутствует; обход с адреса сети вендора решения о бане не даёт, тот же обход с постороннего адреса — даёт;
  недоступный источник прежних сетей не стирает; сеть шире порога в allowlist не попадает; обновление — при деплое,
  вербом и раз в неделю в стеке. Проверка: на стенде `make allowlist` → `docker exec crowdsec cscli allowlists list`
  — сети; `cscli postoverflows list` — оба; 45 строк журнала с разными путями с адреса сети вендора → `cscli
  decisions list` пуст, с `203.0.113.7` → решение; две строки с UA `CCBot` — так же; образ `<asdt>` и
  `make allowlist` → сетей `GPTBot` и `CCBot` нет
- [ ] **AC8** — Смок и приёмка первого деплоя — машиной: `make status` печатает блок `-- site --` (liveness, `/`,
  `robots.txt`, `sitemap.xml`, `X-Robots-Tag` по среде) и состояние edge (журнал читается, allowlist свежий) без
  `ATTENTION` на здоровом стенде; `make accept SVC=site` проходит список § 1.7 в прод- и не-прод профиле, UA-проба —
  по токенам `ai-bots.sources`; каждая поломка набора (§ 4 файла покрытия) даёт `ATTENTION` или красную приёмку.
  Проверка: на стенде `make status` → блоки без `ATTENTION`; `make accept SVC=site` → код 0 в двух профилях; набор
  поломок → 13 из 13 пойманы
- [ ] **AC9** — Список ботов — одна норма: `configs/crowdsec/ai-bots.sources` — печать реестра сайта (первая
  строка — версия реестра), пересобирается одной командой хаба из соседнего `<org>/site`; рукописных списков сетей,
  суффиксов и токенов ботов в `I` нет; расхождение версии с соседом видно в `make doctor`. Проверка:
  `SITE_REPO_PATH=<R> make bots-sources` → `git diff --exit-code configs/crowdsec/ai-bots.sources`, первая строка
  содержит `1ca0e662f76d`; байт в `crawlers.yaml` worktree соседа → `make doctor` → WARN
- [ ] **AC10** — Канон и обвязка хаба — про сайт правдой: `docs/reference/ecosystem.md` (сайт — в стеке из коробки;
  `<org>/site` читает слой страницы, факты и голос, пакет дизайна и `ready.yaml`, как в контракте strategy 0.2.0;
  что хаб делает со строками `AI-BOTS` и `PROXY` handoff), `CLAUDE.md`, `README.md`,
  `docs/reference/{architecture,runbook}.md`, `docs/getting-started.md`, правила, `docs/project/`, скиллы — без
  утверждений «корень — только заглушка», «`site` добавляет `/add-service`», «сайт читает `fsd/`». Проверка:
  grep-список § 5 файла покрытия → «должно быть» найдено, «не должно быть» пусто; чтение валидатором по § 1.6 покрытия
- [ ] **AC11** — Гейт зелёный, умолчания безопасности edge на месте: `sanitizePath` не выключен, `crowdsec@file` — на
  каждом публичном роутере, docker-сокет — только у `traefik`, catch-all роутеров и опубликованных портов сервисов
  нет, dashboard закрыт. Проверка: `make check` на чистом дереве → `✓ check clean`, с поломкой умолчания — красный;
  на стенде `make validate` → `compose syntax PASS`; лог Traefik после деплоя — без ошибок, кроме ACME стенда;
  `grep -rn sanitizePath compose configs` → пусто; `grep -l docker.sock compose/*.yml` → только `compose/traefik.yml`

## Шаги
### Этап A — стенд, edge, сервис
- [x] **S1** — План фазы — в `I/.claude/plans/`, хуки поставлены; стенд `M/p7/stand.sh` поднимает «VPS в контейнере» с
  registry и образом сайта из HEAD `R`; исходная картина на `d8458e3` записана
  - Проверка: `M/exclusive.sh M/p7/stand.sh up d8458e3` → на стенде `make ps`: `traefik`, `crowdsec`, `landing`
    healthy; `M/p7/baseline.log` — три красных факта; `stand.sh down` → `docker ps -a` без `p7-` · Зависит от: —
  - Сделано: `stand.sh` и `baseline.sh` — в `M/p7/`; исходная картина `d8458e3` — `M/p7/baseline.log`
- [x] **S2** — Middleware edge — по § 1.3: `secure-headers` в составе списка (без XSS-фильтра и `sslRedirect`, с
  `Permissions-Policy`), `compress`, `www-to-apex`, `form-rate-limit`, `form-body-limit`, `retry`, `deny-all`, контур
  staging — цепочка `staging` (`staging-noindex` перед `staging-auth`; пользователь замка рендерится из `.env` и не
  попадает в git), отказ WAF — 429
  - Проверка: на стенде `make deploy` → лог Traefik без ошибок конфигурации; `scurl -I https://p7.test/` (заглушка)
    → четыре заголовка edge, `X-XSS-Protection` нет; решение `cscli decisions add` на адрес клиента → 429;
    `make validate` → OK · Закрывает: AC3, AC4, AC5 · Зависит от: S1
  - Сделано: `middlewares.yml.tpl` — состав § 1.3; проба каждого middleware на стенде — `M/p7/s2-check.{sh,log}`
- [x] **S3** — Сервис `site` в стеке и выкатка: `compose/site.yml` по § 1.1 (профиль `site`; роутеры `site`,
  `site-form`, `site-image`, `site-www`; healthcheck контейнера и сервиса Traefik), секция `profile site` в
  `.env.example` и подсказки `make new-env`, `site` в роли `edge`, `www` в DNS-preflight, `make bump` ждёт healthy
  - Проверка: на стенде `make bump SVC=site TAG=<тег>` → код 0, `site` healthy, строка штамповки; `TAG=<битый>` →
    код ≠ 0; curl-строки § 1.7 п. 4, 5, 7, 8 (адрес, методы, `/_image`, `www`, заголовки, серия POST, не-прод
    профиль); `HOST_ROLE=edge` → `make deploy` поднимает `site`; DNS-preflight при профиле `site` называет
    `www.p7.test`; `make validate` → `compose syntax PASS`, `.env coverage PASS` · Закрывает: AC1, AC2, AC3, AC4, AC5
    · Зависит от: S2
  - Сделано: `compose/site.yml`, секция `profile site`, `ROLE_FILES[edge]`, `www` в preflight, `bump` с `--wait`;
    исправления по отчёту валидатора — B1 и N1–N7 в «Решениях». Гейт этапа (`M/p7/stage-a.sh`): 270 проверок, ✗ 0

### Этап B — журнал и CrowdSec
- [ ] **S4** — Журнал доступа — файл `/var/log/traefik/access.log`: JSON, все статусы, `User-Agent` и
  `X-Request-Id`; ротация — в стеке (static-конфиг Traefik — отдельным коммитом)
  - Проверка: на стенде запрос с UA бота → последняя запись журнала: `DownstreamStatus` 200 и `request_User-Agent`;
    `X-Request-Id` ответа `/net-takogo` — в записи журнала и в `make logs SVC=site`; запуск ротации → активный файл
    сброшен, следующая запись — в нём · Закрывает: AC6 · Зависит от: S3
  - Учесть (отчёт валидатора этапа A, § 6 и § 9): тем же коммитом — `providers.docker.allowEmptyServices: true`:
    окно пересоздания он не меняет (1,9 с с ним и без него), зато контейнер без здоровья — неудачная выкатка,
    unhealthy — отвечает 503, а не заглушкой с 200. Рестарт Traefik не бесплатен: плагин bouncer качается из сети при
    каждом старте, сбой загрузки — 404 на всех роутерах до следующего рестарта; шаг рестартует Traefik на каждом
    действующем VPS — машинная сверка `Plugins loaded` после рестарта, строка в runbook и Handoff
- [ ] **S5** — CrowdSec читает журнал и бережёт поисковиков: источник acquisition непуст с первого деплоя чистого
  стенда; постоверфлоу `rdns` и `seo-bots-whitelist` установлены; сценарии обхода срабатывают на постороннем адресе
  - Проверка: свежий стенд → `make deploy` → `cscli metrics show acquisition` — строк источника журнала > 0;
    `cscli postoverflows list` → оба; 45 строк журнала с `ClientHost: 203.0.113.7` и разными путями → в
    `cscli decisions list` решение; запись после ротации журнала читается · Закрывает: AC6, AC7 · Зависит от: S4
  - Учесть (там же, § 9 п. 3): healthcheck `crowdsec` (`cscli version`) LAPI не проверяет — после первого деплоя
    bouncer до 46 с отвечал 429 всем при зелёном `make deploy`; шаг пересоздаёт контейнер — замерить, проверять LAPI
- [ ] **S6** — Allowlist ботов: `configs/crowdsec/ai-bots.sources` — печать реестра сайта командой хаба (версия —
  первой строкой, расхождение с соседом — WARN в `make doctor`); сети источников, которых пускает `robots.txt`
  сервиса, — в `cscli allowlists`: при деплое, вербом `make allowlist` и раз в неделю в стеке; недоступный источник
  не стирает прежние сети, слишком широкая сеть отвергается
  - Проверка: `SITE_REPO_PATH=<R> make bots-sources` → `git diff --exit-code`; на стенде `make allowlist` →
    `cscli allowlists list` — сети; строки журнала с адреса сети вендора (обход и UA `CCBot`) → решения нет; образ
    `<asdt>` → после `make allowlist` сетей `GPTBot` и `CCBot` нет; подставной источник с сетью `/4` → отказ ·
    Закрывает: AC7, AC9 · Зависит от: S5

### Этап C — смок, приёмка машиной, канон
- [ ] **S7** — Смок и приёмка первого деплоя — машиной: `smoke.d/90-site.sh` по § 1.6, состояние edge в смоке
  (журнал читается, allowlist свежий), верб `make accept SVC=site` — список § 1.7 с UA-пробой по токенам
  `ai-bots.sources`
  - Проверка: на стенде `make status` → блоки без `ATTENTION`; `make accept SVC=site` → код 0 в прод- и не-прод
    профиле; поломки набора (§ 4 покрытия) → `ATTENTION` или код ≠ 0 на каждой · Закрывает: AC8 · Зависит от: S6
- [ ] **S8** — Канон экосистемы и документы хаба: `docs/reference/ecosystem.md` (сайт из коробки, что читает
  `<org>/site`, применение строк handoff), `CLAUDE.md`, `README.md`, `docs/reference/architecture.md` (схема, сети,
  роли, журнал и CrowdSec), `runbook.md` (сбои сайта и edge, отчёт «бот × статус»), `docs/getting-started.md`
  - Проверка: grep-список § 5 покрытия по этим файлам → чисто; `make check` → зелёный · Закрывает: AC10 ·
    Зависит от: S7
- [ ] **S9** — Правила и скиллы хаба знают сайт: `multi-env`, `secrets-and-env`, `traefik-routing`,
  `compose-and-services`, `make-first`; `docs/project/` (README, шаблоны); `add-service` (вариант «Node-сервис на
  корневом домене»), `de-template` (сайт → профиль `site`, заглушка прунится), справочники `service-deep-dive`,
  `stack-deep-dive`, `init-project`, `bootstrap-vps`
  - Проверка: grep-список § 5 покрытия по `.claude/` и `docs/project/` → чисто; `make validate` →
    `frontmatter PASS`; `make check` → зелёный · Закрывает: AC10 · Зависит от: S8

### Этап D — приёмка
- [ ] **S10** — Приёмка отдельным агентом, не автором: контракт сайта пункт за пунктом по файлу покрытия на свежем
  стенде — образ из HEAD `R` в registry стенда, первый деплой, `make bump`, приёмка в прод- и не-прод профиле,
  политика `<asdt>`, набор поломок, дренаж (`docker stop site` — код 0 быстрее `stop_grace_period`); `make check` на
  чистом дереве; хвосты — в `backlog.md`, план закрыт
  - Проверка: отчёт `M/acceptance-add-site-service.md` — AC1–AC11 подтверждены, расхождения названы; `make check` →
    `✓ check clean` · Закрывает: AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC8, AC9, AC10, AC11 · Зависит от: S9

## Решения
- Роутер `site-www` не проксирует: сервис — `noop@internal`, regexp `www-to-apex` хост не называет (B1, Р20). `Host()`
  принимает `Host` с портом, заглавными и точкой в конце, а несработавший редирект отдавал такой запрос сайту — мимо
  замка не-прод, лимитов формы и запрета `/_image`. Пробы записей `Host` на каждом роутере — гейт этапа
  (`s3-inner.sh hosts`) и `make accept` (S7).
- Контур не-прод — цепочка `staging@file` (`staging-noindex`, затем `staging-auth`: иначе 401 уходит без
  `X-Robots-Tag`), и включает её сам пароль: хвост цепочек `site` и `site-form` —
  `${STAGING_BASIC_AUTH_USERS:+,staging@file}`. Переменной `SITE_EDGE_EXTRA_MW` нет — замок без пользователей (N1:
  паника Traefik, 404 на всём edge), обратный порядок и опечатка в имени перестали быть состояниями `.env`.
  Пользователь — `users` в `middlewares.yml.tpl`: смену пароля Traefik применяет без рестарта (N4); пустой замок
  рендерится пользователем без пароля — снятие замка не роняет сборку роутеров. Значение не вида `'user:hash'`
  отвергают `make render`, `make deploy` до `compose up` и `make doctor` (`scripts/preflight-env.sh`; Р15, Р17, Р21).
- Хеш замка — только bcrypt целиком, логин — латинские буквы, цифры и `._@-` (Р23): открытый пароль и обрезанный
  хеш дают замок, под которым не войти, `{{` в логине — отказ Traefik от всего dynamic-файла, а деплой при этом
  зелёный. MD5 и SHA1 `basicAuth` принимает, но способ один — `htpasswd -nbB`, и он самый стойкий.
- Строка `.env` — одной формы: `KEY=значение` с начала строки, значение с пробелом, `$`, кавычкой или знаком шелла —
  в одинарных кавычках. Форму держит `scripts/preflight-env.sh` раньше каждого чтения файла — `make deploy`,
  `render`, `doctor`, `validate` и ops-вербы (`env-form` в `Makefile`): на строке другой формы bash и compose сами
  печатают её кусок — хеш, пароль. Цена: `.env` с `$`-подстановкой, `export` или многострочным значением отвергается.
- `DOMAIN` — запись хоста, какой её принимает сайт (`SITE_URL`): строчные, IDN — в punycode, без схемы, порта, пути
  и точки на конце. При профиле `site` другую запись preflight отвергает до деплоя — образ сайта с ней не стартует,
  и `make deploy` узнавал об этом по нездоровому контейнеру; без профиля — предупреждение: стеку без сайта она не
  мешает (Р24).
- `make bump` при отказе возвращает прежний тег в `.env` и поднимает сервис на нём, код ≠ 0 (N2, Р22): тег без образа
  оставлял `.env`, на котором падает `make deploy`, битый образ — заглушку с 200 на корне. Первый тег остаётся.
- Умолчания edge — статикой в `make validate` (`edge defaults`, без docker и `.env`; N5), по сервисам: цепочка роутера
  начинается с `crowdsec@file`, правило называет `Host`, сервис с включённым роутером не публикует порт, docker-сокет
  — только у сервиса `traefik`, `sanitizePath` не задан, сосед каждого `.tpl` — под `.gitignore`. Пределы записаны в
  шапке проверки: она читает текст labels, роутеры file-провайдера не видит. Пробой — S7: `make accept` (записи
  `Host`, отказ WAF 429, лишние заголовки, порядок цепочки `staging`), смок (на `/` отвечает не сайт, не-прод без
  замка), `doctor` — пустой `<SVC>_TAG` (N8). Ожидание healthy и возврат тега в `bump` держит гейт этапа.
- `make new-env` пишет `ROBOTS_POLICY` по `ENV` (`prod` — `index`, иначе `noindex`) и `HOST_ROLE=all` (N6, Р6):
  свежий `.env` покрывает активные ключи `.env.example` — `make doctor` без WARN, не-прод закрыт от индексации сразу.
- Журнал — файл в каталоге хоста `/var/log/traefik`, не docker-источник: `acquis.yaml` и монтирование `/var/log` у
  `crowdsec` рассчитаны на этот путь; docker-сокет второму контейнеру — права тому, кто разбирает чужой ввод.
- Расписание (ротация журнала, обновление allowlist) живёт в стеке, как cron бэкапа, а не на хосте: правка доезжает
  `make deploy` без ansible и проверяется на стенде. Где крутится `crond` — выбор исполнителя по фактам образа.
- Отказ WAF — 429 (`remediationStatusCode` плагина): боту без списка вендора и ложному срабатыванию это «приходи
  позже», а не «страницы нет»; защита не слабее — запрос так же не доходит до сервиса.
- Отказ тела сверх лимита Traefik пишет в лог уровнем `ERR` (`vulcand/oxy/buffer`): это ответ 413, а не ошибка
  конфигурации — проверка «лог без ошибок» (AC11) такие строки не считает.
- Healthcheck `site` — с `start_interval: 1s`: роутеры контейнера в состоянии `starting` docker-провайдер Traefik не
  строит, и при пересоздании ~5 с отвечала заглушка (стало ~2 с — ниже держит `providersThrottleDuration`; Р18).
  Ключу нужен Docker Engine ≥ 25 (N7): версию называет `make doctor`, обновление движка — runbook.
- Первый разворот: профиль `site` в `.env`, затем `make bump` (ставит `SITE_TAG`); профиль без тега роняет
  `make deploy` (`invalid reference format`), `bump` без профиля поднимает сервис мимо `make deploy` (Р19).
- Политику сайта задание allowlist читает с `robots.txt` сервиса (`site:3000`), не через публичный адрес: на не-прод
  тот отвечает 401. Нет сервиса `site` или ответа — allowlist не меняется.
- Список источников — файл хаба из печати контракта, а не копия реестра; общий список трёх ботов Anthropic идёт в
  allowlist, пока политика пускает хотя бы одного, — по адресу их не различить. Сеть шире порога (исполнитель S6)
  отвергается: чужой ответ не открывает edge. Записи allowlist живут со сроком — убранная вендором сеть уходит сама.
- Локальная rDNS-страховка не делается: суффиксы Яндекса несёт `seo-bots-whitelist` хаба CrowdSec.
- Заглушка `landing` остаётся always-on и держит выпуск сертификата корня до первого деплоя сайта; при сайте на корне
  её прунит `/de-template`. Профиль памяти — 512 МБ и `--max-old-space-size=384` (предложения контракта).
- Правка static-конфига Traefik и контракта `.env.example` — граница «сначала спросить» обвязки `I`; основание —
  строка фазы P7 программы, принятой владельцем («`User-Agent` в access-log»), и § 1.4 контракта.
- Имя сервиса `site` — умолчание шаблона и поле `infra-svc` форка; поверхность с другим именем заводит `/add-service`.
- Канон «кто что читает из strategy» пишется по контракту strategy 0.2.0 (R01); документы `R` догоняют его в P8.
- Приёмка § 1.7 — верб хаба: страницу для проверок формы адреса берёт из `sitemap.xml` сайта (у форка нет `/about`),
  UA — из токенов `ai-bots.sources`. Приёмка фазы — на стенде шаблона: `make accept` на живом VPS до закрытия фазы
  не нужен (решение владельца); сертификаты apex и `www`, настоящие адреса ботов — приёмка первого деплоя проекта.

## Handoff
- Репо сайта (через дирижёра): расхождения и уточнения контракта — § 3 файла покрытия.
- Оператору форка: секция `profile site` в `.env` (тег, канал формы, на не-прод — `ROBOTS_POLICY=noindex` и замок),
  DNS-запись `www`, Docker Engine ≥ 25 на VPS, после первого деплоя — `make accept SVC=site`. Обновление действующего
  VPS: `make deploy` рестартует Traefik (static-конфиг) — секунды простоя; с полным журналом сценарии обхода
  CrowdSec начинают работать — свой аудит с рабочей станции может получить 429 (runbook).
- Бэклог `I` (не тема фазы): `make validate` без `.env` не разбирает compose и не ловит `:latest`, хотя проза это
  обещает; источник `auth.log` у CrowdSec пуст на Debian 12 без rsyslog; `deploy.sh` глотает отказ
  `git pull --ff-only`; роутеры file-провайдера (`dynamic/*.yml`) проверка `edge defaults` не читает; API Traefik из
  контейнера (правило `traefik-routing`) отвечает 404.

## Где мы сейчас
Этап A (S1–S3) принят независимым валидатором на `e5de963` (первый проход — FAIL на B1; исправления и перепроверка —
`M/validation-add-site-service-A.md`). Идёт этап B: неблокирующие остатки перепроверки закрываются коммитами `fix`
(пробы — `M/p7/stage-b/fix-*`), затем S4–S6 по пометкам «Учесть».
