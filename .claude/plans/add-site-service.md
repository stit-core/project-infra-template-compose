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
  `/home/mm/git/stit-core/ssr-frontend-template` (только чтение); `M` = `/home/mm/git/stit-core/stit-ssr-audit`:
  прогоны и гейты — `M/p7/`, образ сайта — из worktree `M/wt-p7-site` на HEAD `R`.
- **Метод** — `R/.claude/plans/audit-program.md` (R16–R18, R01): этап → исполнитель → независимый валидатор → фиксы →
  перепроверка; шаг — коммит, план — тем же коммитом, трейлер `Co-Authored-By`; `make ship` в фазе не используется
  (push — после закрытия фазы); static-конфиг Traefik — отдельным коммитом (`CLAUDE.md`, «сначала спросить»).
- **Контракт** — `R/docs/reference/infra-handoff.md` § 1.1–1.7, реестр ботов `src/shared/seo/crawlers.yaml`
  (`1ca0e662f76d`, политика HEAD — `allow-all`) и его печать `pnpm bots:sources`. **Покрытие** —
  `M/plans/add-site-service.coverage.md`: контракт (§ 1), находки (§ 2), расхождения (§ 3), набор поломок (§ 4),
  grep-список прозы (§ 5), факты проб (§ 7).
- **Стенд** — «VPS в контейнере» `M/p7/stand.sh` (команды — в шапке): `p7-vps` без проброса портов, registry
  `127.0.0.1:5000`, клон `I` в `/opt/p7-infra`, `.env` от `make new-env` (`DOMAIN=p7.test`); `sync` везёт рабочее
  дерево через `git pull` из `make deploy`. «На стенде `X`» = `M/exclusive.sh M/p7/stand.sh sh 'X'`; `scurl` —
  `curl -sk` с `--resolve` на стенд. Теги: `<тег>` = `v1.0.0`, `<битый>` = `v1.0.1-broken` (без `/healthz`),
  `<asdt>` = `v1.0.2-asdt`.
- **Гейт шага:** `make check` → `✓ check clean` и проверка шага на стенде. **Гейт этапа:** проверки шагов и регресс
  прошлых на свежем стенде с нуля — `M/p7/stage-{a,b,c}.sh`; исполнитель и, независимо, валидатор.

## Не входит
- Живой VPS и домен: сертификаты Let's Encrypt (apex и `www`), DNS-записи, pull из registry с PAT, ansible-bootstrap,
  баны настоящих адресов, TTFB из сети, `/seo-audit` по прод-домену (§ 1.7 п. 10) — приёмка первого деплоя проекта.
- Правки `R` и текста контракта: расхождения — § 3 файла покрытия, их возвращает в репо сайта дирижёр. Задания
  разделов 2–3 контракта (`spa-frontend-template`, `stit-public`).
- Compose-фрагменты SPA и бота; вторая поверхность сайта на том же VPS (её заводит `/add-service` по варианту S9).
- Локальная rDNS-страховка `seo-bots-local.yaml` (§ 1.5, опция), AppSec CrowdSec, CDN перед Traefik, капча; хвосты
  обвязки `I` вне темы сайта — строками в `backlog.md` (раздел «Handoff»).

## Критерии приёмки
- [x] **AC1** — `make bump SVC=site` проходит на стенде шаблона (критерий фазы программы): на чистом стенде при
  профиле `site` и заполненной секции `.env` выкатка образа сайта из registry даёт здоровый сервис со штамповкой
  origin; образ, который не становится healthy, и тег без образа — отказ верба; возврат на рабочий тег — снова healthy.
  Проверка: на стенде `make bump SVC=site TAG=<тег>` → код 0, `make ps` → `site` healthy, `make logs SVC=site` →
  `[entrypoint] stamped https://__site_origin__ -> https://p7.test`; `TAG=<битый>` и тег без образа → код ≠ 0
  - Подтверждено: гейт этапа A (`M/p7/stage-a-s3.log`): healthy за 6 с, штамповка; отказ возвращает прежний тег
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
  - Подтверждено: гейт этапа A (`stage-a-s3.log`): пять заголовков и `br`, лишних нет; у заглушки — четыре edge
- [x] **AC4** — Избыточный трафик получает 429, а не 403: серия POST на `/api/contact` упирается в лимит формы, и
  заявка сверх лимита до процесса не доходит; тело формы больше 64 КиБ без `Content-Length` — 413 от edge; отказ WAF
  (решение CrowdSec о бане) — тоже 429; у лимитов нет `sourceCriterion`, в цепочке формы нет `retry` и `compress`.
  Проверка: на стенде 8 POST с `Origin: https://p7.test` и незаполненной формой → пять ответов формы (200), затем
  429, ни одного 403 и 303; вне серии chunked-тело 70 КБ → 413; `cscli decisions add --ip <адрес клиента>` → через
  ≤ 60 с `/` — 429, после `decisions delete` — 200
  - Подтверждено: гейт этапа A (`stage-a-s3.log`): серия — `200` × 5, `429` × 3; chunked 70 КБ — 413; решение — 429
- [x] **AC5** — Не-прод закрыт тремя контурами и включается ключами `.env`: при `ROBOTS_POLICY=noindex` и замке
  `STAGING_BASIC_AUTH_USERS` `/` без пароля — 401 с `X-Robots-Tag: noindex, nofollow, noarchive`, с паролем — 200 с
  тем же заголовком, `robots.txt` сервиса — `Disallow: /`; ни одна запись `Host` не отдаёт страницу без пароля; при
  пустом замке ни его, ни заголовка edge нет; хеш замка в git не попадает; замок, который `basicAuth` не разберёт, —
  отказ до деплоя. Проверка: стенд в не-прод профиле — `scurl -I https://p7.test/` → 401 и заголовок, `scurl -u
  <пользователь>:<пароль>` → 200; `curl -H 'Host: www.p7.test:443' https://www.p7.test/<страница>` → 301;
  `git status --short` после `make render` → чисто; замок без `:` → `make deploy` — код ≠ 0 до `compose up`;
  прод-профиль → 200 без `X-Robots-Tag`
  - Подтверждено: гейт этапа A (`stage-a-s3.log`): 401 с `X-Robots-Tag`, с паролем — 200; битый замок — отказ
- [x] **AC6** — Журнал доступа полон и читается: каждая запись, и 2xx, — JSON-строка в `/var/log/traefik/access.log`
  с `request_User-Agent`; `X-Request-Id` ответа on-demand маршрута есть и в записи журнала, и в строке лога сайта;
  CrowdSec читает журнал с первого деплоя; ротация идёт в стеке без действий оператора и чтения не рвёт. Проверка: на
  стенде `scurl -A 'Mozilla/5.0 (compatible; OAI-SearchBot/1.0)' https://p7.test/` → `tail -1
  /var/log/traefik/access.log | jq '.DownstreamStatus, ."request_User-Agent"'` → 200 и UA; `docker exec crowdsec cscli
  metrics show acquisition` сразу после первого `make deploy` → строк источника > 0; после ротации активный файл
  сброшен, новая запись читается
  - Подтверждено: гейт этапа B (`M/p7/stage-b/stage-b.log`): запись 200 с UA и `X-Request-Id`, чтение — с первого деплоя
- [x] **AC7** — CrowdSec не режет тех, кого пускает сайт: поисковики — постоверфлоу `rdns` и `seo-bots-whitelist`;
  ИИ-боты — allowlist сетей вендоров по `ai-bots.sources` и политике `robots.txt` сервиса: при `allow-all` — сети
  всех строк с `ip_list_url`, включая обучающих; бот, закрытый именной группой, после обновления в allowlist
  отсутствует; обход с адреса сети вендора решения о бане не даёт, тот же обход с постороннего адреса — даёт;
  недоступный источник прежних сетей не стирает; сеть шире порога в allowlist не попадает; обновление — при деплое,
  вербом и раз в неделю в стеке. Проверка: на стенде `make allowlist` → `docker exec crowdsec cscli allowlists list`
  — сети; `cscli postoverflows list` — оба; 45 строк журнала с разными путями с адреса сети вендора → `cscli
  decisions list` пуст, с `203.0.113.7` → решение; две строки с UA `CCBot` — так же; образ `<asdt>` и
  `make allowlist` → сетей `GPTBot` и `CCBot` нет
  - Подтверждено: гейт этапа B (`stage-b.log`): 20 allowlist, обход из сети вендора — без решения; `<asdt>` — 4 сняты
- [x] **AC8** — Смок и приёмка первого деплоя — машиной: `make status` печатает блок `-- site --` (liveness, `/`,
  `robots.txt`, `sitemap.xml`, `X-Robots-Tag` по среде) и состояние edge (журнал читается, allowlist свежий) без
  `ATTENTION` на здоровом стенде; `make accept SVC=site` проходит список § 1.7 в прод- и не-прод профиле, UA-проба —
  по токенам `ai-bots.sources`; каждая поломка набора (§ 4 файла покрытия) даёт `ATTENTION` или красную приёмку.
  Проверка: на стенде `make status` → блоки без `ATTENTION`; `make accept SVC=site` → код 0 в двух профилях; набор
  поломок → 13 из 13 пойманы
  - Подтверждено: гейт этапа C (`M/p7/stage-c/stage-c.log`): `make status` без `ATTENTION`, `make accept` — код 0
    (прод — 45 проверок, не-прод — 32); поломки — 13 из 13 (П8–П10, П12 — ещё и `ATTENTION`)
- [x] **AC9** — Список ботов — одна норма: `configs/crowdsec/ai-bots.sources` — печать реестра сайта (первая
  строка — версия реестра), пересобирается одной командой хаба из соседнего `<org>/site`; рукописных списков сетей,
  суффиксов и токенов ботов в `I` нет; расхождение версии с соседом видно в `make doctor`. Проверка:
  `SITE_REPO_PATH=<R> make bots-sources` → `git diff --exit-code configs/crowdsec/ai-bots.sources`, первая строка
  содержит `1ca0e662f76d`; байт в `crawlers.yaml` worktree соседа → `make doctor` → WARN
  - Подтверждено: `M/p7/stage-b/s6-sources.log` — печать без изменений, версия `1ca0e662f76d`, байт у соседа — WARN
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
  - Сделано: `M/p7/stand.sh`, исходная картина — `M/p7/baseline.log`
- [x] **S2** — Middleware edge — по § 1.3: `secure-headers` в составе списка (без XSS-фильтра и `sslRedirect`, с
  `Permissions-Policy`), `compress`, `www-to-apex`, `form-rate-limit`, `form-body-limit`, `retry`, `deny-all`, контур
  staging — цепочка `staging` (`staging-noindex` перед `staging-auth`; пользователь замка рендерится из `.env` и не
  попадает в git), отказ WAF — 429
  - Проверка: на стенде `make deploy` → лог Traefik без ошибок конфигурации; у заглушки четыре заголовка edge;
    решение `cscli decisions add` на адрес клиента → 429 · Закрывает: AC3, AC4, AC5 · Зависит от: S1
  - Сделано: `middlewares.yml.tpl` — состав § 1.3; пробы — `M/p7/s2-check.{sh,log}`
- [x] **S3** — Сервис `site` в стеке и выкатка: `compose/site.yml` по § 1.1 (профиль `site`; роутеры `site`,
  `site-form`, `site-image`, `site-www`; healthcheck контейнера и сервиса Traefik), секция `profile site` в
  `.env.example` и подсказки `make new-env`, `site` в роли `edge`, `www` в DNS-preflight, `make bump` ждёт healthy
  - Проверка: на стенде `make bump SVC=site TAG=<тег>` → код 0, `site` healthy, строка штамповки; `TAG=<битый>` →
    код ≠ 0; curl-строки § 1.7 п. 4, 5, 7, 8; `HOST_ROLE=edge` → `make deploy` поднимает `site`; `make validate` →
    `compose syntax PASS` · Закрывает: AC1, AC2, AC3, AC4, AC5 · Зависит от: S2
  - Сделано: `compose/site.yml`, секция `profile site`, `ROLE_FILES[edge]`, `www` в preflight, `bump` с `--wait`;
    гейт этапа A (`M/p7/stage-a.sh`): 270 проверок, ✗ 0

### Этап B — журнал и CrowdSec
- [x] **S4** — Журнал доступа — файл `/var/log/traefik/access.log`: JSON, все статусы, `User-Agent` и
  `X-Request-Id`; ротация — в стеке (static-конфиг Traefik — отдельным коммитом)
  - Проверка: на стенде запрос с UA бота → последняя запись журнала: `DownstreamStatus` 200 и `request_User-Agent`;
    `X-Request-Id` ответа `/net-takogo` — в записи журнала и в `make logs SVC=site`; запуск ротации → активный файл
    сброшен, следующая запись — в нём · Закрывает: AC6 · Зависит от: S3
  - Сделано: журнал — файл каталога хоста, ротация — crond рядом с CrowdSec, `allowEmptyServices` (`stage-b/s4-*.log`)
- [x] **S5** — CrowdSec читает журнал и бережёт поисковиков: источник acquisition непуст с первого деплоя чистого
  стенда; постоверфлоу `rdns` и `seo-bots-whitelist` установлены; сценарии обхода срабатывают на постороннем адресе
  - Проверка: свежий стенд → `make deploy` → `cscli metrics show acquisition` — строк источника журнала > 0;
    `cscli postoverflows list` → оба; 45 строк журнала с `ClientHost: 203.0.113.7` и разными путями → в
    `cscli decisions list` решение; запись после ротации журнала читается · Закрывает: AC6, AC7 · Зависит от: S4
  - Сделано: здоровье `crowdsec` — готовность LAPI и живой crond, источник журнала — с `force_inotify` (`s5-*.log`)
- [x] **S6** — Allowlist ботов: `configs/crowdsec/ai-bots.sources` — печать реестра сайта командой хаба (версия —
  первой строкой, расхождение с соседом — WARN в `make doctor`); сети источников, которых пускает `robots.txt`
  сервиса, — в `cscli allowlists`: при деплое, вербом `make allowlist` и раз в неделю в стеке; недоступный источник
  не стирает прежние сети, слишком широкая сеть отвергается
  - Проверка: `SITE_REPO_PATH=<R> make bots-sources` → `git diff --exit-code`; на стенде `make allowlist` →
    `cscli allowlists list` — сети; строки журнала с адреса сети вендора (обход и UA `CCBot`) → решения нет; образ
    `<asdt>` → после `make allowlist` сетей `GPTBot` и `CCBot` нет; подставной источник с сетью `/4` → отказ ·
    Закрывает: AC7, AC9 · Зависит от: S5
  - Сделано: `make bots-sources`, сверка версии в `doctor`, задание `configs/crowdsec/bots-allowlist.sh` — верб, шаг
    деплоя, расписание; гейт этапа B (`M/p7/stage-b.sh`): ✓ 213, ✗ 0, регресс этапа A — ✗ 0

### Этап C — смок, приёмка машиной, канон
- [x] **S7** — Смок и приёмка первого деплоя — машиной: `smoke.d/90-site.sh` по § 1.6, состояние edge в смоке
  (журнал читается, allowlist свежий), верб `make accept SVC=site` — список § 1.7 с UA-пробой по токенам
  `ai-bots.sources`
  - Проверка: на стенде `make status` → блоки без `ATTENTION`; `make accept SVC=site` → код 0 в прод- и не-прод
    профиле; поломки набора (§ 4 покрытия) → `ATTENTION` или код ≠ 0 на каждой · Закрывает: AC8 · Зависит от: S6
  - Сделано: `smoke.d/90-site.sh`; `smoke.d/30-edge.sh` — журнал, чтение пробой через edge, сверка allowlist и банов
    (режим `state` задания); `make accept SVC=site` (`scripts/tools/accept.sh`); пустой тег образа — FAIL `doctor`.
    Гейт этапа C на свежем стенде (`M/p7/stage-c.sh`): ✓ 286, ✗ 0; регресс этапов A и B — ✗ 0
- [x] **S8** — Канон экосистемы и документы хаба: `docs/reference/ecosystem.md` (сайт из коробки, что читает
  `<org>/site`, применение строк handoff), `CLAUDE.md`, `README.md`, `docs/reference/architecture.md` (схема, сети,
  роли, журнал и CrowdSec), `runbook.md` (сбои сайта и edge, отчёт «бот × статус»), `docs/getting-started.md`
  - Проверка: grep-список § 5 покрытия по этим файлам → чисто; `make check` → зелёный · Закрывает: AC10 ·
    Зависит от: S7
  - Сделано: ecosystem — чтение strategy по её контракту, «Handoff-блок релиза» и первый релиз сайта; runbook —
    `ATTENTION` смока, ✗ приёмки, сбои сайта, отчёт «бот × статус»; § 5 по файлам S8 — ✗ 0, `make check` — зелёный
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
- Обоснования этапов A и B — в правилах `traefik-routing`, `secrets-and-env`, `compose-and-services`, runbook и § 3.
- Роутер `site-www` не проксирует (`noop@internal`, regexp `www-to-apex` без хоста): несработавший редирект отдавал
  запрос сайту мимо замка, лимитов формы и запрета `/_image`. Контур не-прод — цепочка `staging@file`
  (`staging-noindex`, затем `staging-auth`: иначе 401 без `X-Robots-Tag`); включает её сам пароль — хвост цепочек
  `${STAGING_BASIC_AUTH_USERS:+,staging@file}`, пользователь — `users` в dynamic-конфиге (смена пароля — без рестарта
  Traefik).
- `make bump` при отказе возвращает прежний тег в `.env` и поднимает сервис на нём; первый разворот — профиль `site`,
  затем `make bump` (ставит `SITE_TAG`). `make new-env` пишет `ROBOTS_POLICY` по `ENV` и `HOST_ROLE=all`.
  Healthcheck `site` — `start_interval: 1s`: роутеры контейнера в `starting` Traefik не строит (Engine ≥ 25 —
  `make doctor`).
- `scripts/preflight-env.sh` отказывает до рендера и compose (`render`, `deploy`, `doctor`; форма строк — ещё
  `validate` и ops-вербы): замок — не `'user:hash'` с логином из `A-Za-z0-9._@-` и bcrypt целиком (Р23); `DOMAIN` — не
  запись хоста при профиле `site` (Р24); строка `.env` — не `KEY=значение`, где значение с пробелом, `$`, кавычкой или
  знаком шелла — в одинарных кавычках, а после него ничего нет (Р25): строку другой формы шелл и compose читают
  по-разному и печатают её кусок. Цена: `$`-подстановка, `export`, хвостовой комментарий, многострочное значение.
- Статикой `make validate` держит умолчания edge (`edge defaults`, пределы — в шапке проверки) и скрипты стека
  (`stack scripts`); то, что статикой не взять, — смок, `make accept` и `doctor` (S7, ниже).
- Журнал — файл каталога хоста `/var/log/traefik`, не docker-источник: сокет второму контейнеру — права тому, кто
  разбирает чужой ввод. Расписание edge (ротация, allowlist) — `crond` рядом с CrowdSec: заданиям нужны `cscli` и
  каталог журнала. Ротация — копия и сброс активного файла раз в сутки и вне очереди при 256 МиБ, 14 сжатых копий:
  Traefik переоткрывает журнал только по сигналу; копия — раньше сдвига прежних. Права — по минимуму читателей: каталог
  журнала — `700` root, отрендеренные конфиги Traefik (ключ bouncer, хеш замка) — `600`; их читают Traefik, CrowdSec
  и задания root'ом, страницу заглушки (`644`) — nginx не root'ом.
- `allowEmptyServices: true` (Р18, Р27): неудачная выкатка отвечает 5xx от edge (первые секунды 500, затем 503), а
  не заглушкой с 200; окно успешной выкатки (~2 с) остаётся — в нём заглушка, иногда 500 или 502.
- Сбой загрузки плагина bouncer — отказ старта Traefik (`abortOnPluginFailure`), а не 404 на всём edge при `healthy`:
  контейнер перезапускает политика `restart`, edge закрыт и возвращается сам; `make deploy` после рестарта по дифу
  конфигов ждёт healthy и без него отказывает. Петля рестартов в смоке — перезапуск сейчас или второй рестарт за 10
  минут: `RestartCount` копится с создания контейнера, и разовый сбой загрузки — строка `restarts` без `ATTENTION`.
- Здоровье `crowdsec` — ответ LAPI (`/health`) и живой crond: пока LAPI не отвечает, bouncer отказывает всем (429), и
  Traefik стартует после него; лог LAPI пишет строку на каждую пробу и каждый вопрос bouncer — его читают `grep`.
  Источник журнала — с `force_inotify`: файла журнала на старте CrowdSec ещё нет (Р28).
- Поисковиков бережёт rDNS: `rdns` и `seo-bots-whitelist` несёт `whitelist-good-actors` — зависимость коллекции
  `crowdsecurity/linux` (Р26); Яндекса — только он. Это один запрос PTR при переполнении сценария, без ответа — бан на
  4 ч; резолвер контейнера повторяет запрос до пяти раз (`dns_opt`). Остаток риска — runbook и сигнал смока о банах
  поисковиков (Р31).
- Отказ WAF — 429 (`remediationStatusCode`): боту без списка вендора и ложному срабатыванию это «приходи позже», а не
  «страницы нет». Отказ тела сверх лимита Traefik пишет в лог уровнем `ERR` — это ответ 413, не ошибка.
- Allowlist — по списку на бота, `bot-<токен>` (три бота Anthropic — один адрес). Политику задание читает с
  `robots.txt` сервиса (`site:3000`): публичный адрес не-прод отвечает 401. Закрывает бота только именная группа с
  `Disallow: /`: при `deny-all` остаются `Google-Agent`, `Google-GeminiNotebook`, `Amzn-User` (Р30), при `noindex`
  группы нет — идут все боты со списком. Нет ответа сервиса — allowlist не меняется (Р29).
- Ответ вендора — недоверенные данные: значения ключей `ipv4Prefix`, `ipv6Prefix`, `ip_prefix`, `ipv6_prefix` в форме
  адреса или сети, ответ — целиком и до 2 МиБ; список принимается целиком (B1): до 4096 сетей семейства, до 2^18
  адресов IPv4 и 2^16 сетей `/64` (у реестра — до 1292 сетей, 70 016 адресов у Google-Agent с `/16` — запас ×3,7), без
  частных, служебных и зарезервированных; сети для документации проходят — трафика с них нет, на них пробы стенда.
  Удачный ответ заменяет список, отказ прежних сетей не стирает, срок 21 день снимает сети замолчавшего источника.
- Задание allowlist — два процесса (B2): работу ведёт дочерний своей группой и под `timeout` 600 с, замок держат оба —
  без надзирающего (SIGKILL) задание остаётся одним и видно в `state`; попытка загрузки — 30 с, попыток — до четырёх.
  Загрузки и их помощник `ssl_client` замка не наследуют, а по концу задания и по сроку снимаются его группой — её
  снимает и надзирающий, и само задание. Замок занят дольше срока задания — WARN и код 2 у верба и шага деплоя и
  `ATTENTION` в смоке (`smoke.d/30-edge.sh`).
- Редирект источника — один и только по `https`, на другой хост тоже: его назначает сам вендор под TLS (у Perplexity
  адрес списка отвечает редиректом на `www.perplexity.ai`), задание называет такой список и хост строкой вывода;
  список за вторым редиректом не принимается. Адрес Perplexity в реестре не правится: реестр — копия базы strategy с
  её первоисточником (решение дирижёра). `wget` образа редиректу следует сам — запрос уходит (GET), ответ отбрасывается.
- `make deploy` обновляет только недостающие и не обновлявшиеся шесть дней списки, все — `make allowlist` и
  расписание; после смены политики сайта — `make allowlist` после `make bump` (канон строки `AI-BOTS` — S8).
  `deploy.sh`, обновлённый тем же `git pull`, продолжает новой версией (`exec`); рестарт по дифу конфигов — от ревизии,
  которую сервисы уже подхватили (`refs/deploy/ok` пишут рестарт и конец деплоя): отказ после pull диф не уносит.
- Заглушка `landing` остаётся always-on и держит выпуск сертификата корня до первого деплоя сайта; при сайте на корне
  её прунит `/de-template`. Профиль памяти — 512 МБ и `--max-old-space-size=384` (предложения контракта).
- Правка static-конфига Traefik и контракта `.env.example` — граница «сначала спросить»; основание — строка фазы P7
  программы, принятой владельцем, и § 1.4 контракта. Имя сервиса `site` — умолчание шаблона и поле `infra-svc`
  форка; канон «кто что читает из strategy» — по контракту strategy 0.2.0 (R01).
- Смок edge: журнал — размер от 512 МиБ и запись старше 26 ч (ротация не идёт); чтение источника — проба через edge
  обязана прибавить строку к прочитанным (без пробы «0 строк» не отличить от тихого часа); allowlist и баны — сверка
  самого задания (`state`, без замка): нужные по `robots.txt` против записанных, возраст до 8 дней, сети в пределах,
  лишние; бот под баном — адрес из allowlist или PTR бота без списка сетей (Яндекс): верный адрес бота со списком
  держит allowlist, а суффиксы вроде `googleusercontent.com` носят и чужие ВМ (Р34).
- Смок сайта и приёмка берут домен и среду у контейнера (`SITE_URL`, `ROBOTS_POLICY`, `staging@file` в цепочке), не
  из `.env`: смок `.env` не читает, приёмка проверяет развёрнутое. Профиль приёмки — по замку: не-прод — то, что видно
  без пароля; дренаж не проверяется — он останавливает сайт (Р33); TLS — строка без оценки (стенд — самоподписанный).
  Отказ WAF — решением на адрес временного клиента в сети `proxy`: у нового адреса нет вердикта в кеше bouncer, а
  шлюз сети — адрес всех запросов с хоста (Р32). Страница — из `sitemap.xml` сайта, UA — токены `ai-bots.sources`.
- `make doctor`: пустой `<SVC>_TAG` включённого сервиса — FAIL (`make deploy` упадёт на ссылке образа). Приёмка
  фазы — на стенде шаблона (решение владельца); сертификаты и настоящие адреса ботов — первый деплой проекта.
- Handoff-блок релиза — одна норма, шаги в `ecosystem.md` (`CLAUDE.md`, runbook — ссылкой); на не-прод замок и
  `make deploy` — до профиля `site`: `make bump` конфиги не рендерит (Р36); `make accept SVC=site` — после каждой
  выкатки (заявки и чужих решений не оставляет); отчёт «бот × статус» — с копиями ротации (Р28); R-сторона — Р35.

## Handoff
- Репо сайта (через дирижёра): расхождения и уточнения контракта — § 3 файла покрытия (этап B — Р23–Р31, C — Р32–Р36).
- Оператору форка: первый релиз сайта на среде — `ecosystem.md` («Handoff-блок релиза»: DNS `www`, Docker Engine ≥ 25,
  секция `profile site`, `make bump`, `make accept SVC=site`). Обновление действующего VPS (runbook): строки `.env` не
  той формы — `ENV-ERR` первого `make deploy` до compose; прежний `deploy.sh` allowlist не создаст — `make deploy`
  второй раз; пересоздание Traefik и CrowdSec — 10–11 с без ответа; свой аудит может получить 429 от CrowdSec.
- Бэклог `I` (не тема фазы): `make validate` без `.env` не разбирает compose и не ловит `:latest`; `auth.log` у
  CrowdSec пуст на Debian 12 без rsyslog; `deploy.sh` глотает отказ `git pull --ff-only`; роутеры file-провайдера
  `edge defaults` не читает; API Traefik из контейнера — 404; плагин bouncer качается при каждом старте Traefik
  (версию закрепляет `hash`); заглушка после пересоздания отвечает через 30 с.

## Где мы сейчас
Этапы A, B приняты; этап C: S7 и замечания B — `743dbf0`…`c78e311` (гейт `M/p7/stage-c.sh`: ✓ 286, ✗ 0), S8 — канон
и документы хаба. Дальше — S9 (правила, `docs/project/`, скиллы; § 5 покрытия), затем валидатор этапа C и приёмка S10.
