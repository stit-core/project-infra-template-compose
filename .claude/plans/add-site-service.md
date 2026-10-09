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
- **Пути.** `I` = `/home/mm/git/stit-core/project-infra-template-compose` (ветка `main`, одна пишущая рука — основное
  дерево); `R` = `/home/mm/git/stit-core/ssr-frontend-template` (потребитель контракта, только чтение; образ сайта —
  из worktree `M/wt-p7-site` на HEAD `R`); `M` = `/home/mm/git/stit-core/stit-ssr-audit`; выходы прогонов — `M/p7/`;
  валидаторы и приёмка — в своих `git -C I worktree add --detach M/wt-p7-<имя>`.
- **Метод и решения владельца** — `R/.claude/plans/audit-program.md`: этап → исполнитель → независимый валидатор →
  фиксы → перепроверка, шаг — коммит, план — тем же коммитом; R16, R17 (CSP — приложение, `/_image` закрыт на edge),
  R18 (политика ИИ-ботов — поле сборки сайта), R01 (вход сайта — слой страницы, пакет дизайна, `ready.yaml`). Промпты
  `M/prompts.md` — с заменами: репо — `I`, гейт — `make check`, план — этот. `make ship` в фазе не используется (он
  пушит и деплоит): коммит — `git commit`, push — после закрытия фазы. Фаза стартует после закрытия P3.
- **Контракт.** `R/docs/reference/infra-handoff.md` на HEAD `R` `771461e` (файл — `cc5e2df`), § 1.1–1.7; рядом —
  `deployment.md` (env-контракт, обёртка, требования к прокси), `observability.md § Боты в access-log`,
  `rendering.md § Нормализация URL`, скилл `/release` (строка `AI-BOTS`), реестр `src/shared/seo/crawlers.yaml`
  (sha256 `1ca0e662f76d…`, политика HEAD — `allow-all`). Покрытие пункт за пунктом, расхождения с контрактом, набор
  поломок приёмки и grep-список прозы — `M/plans/add-site-service.coverage.md`. Контракт движется вместе с `R`:
  исполнитель этапа сверяет `git -C R log cc5e2df.. -- docs/reference/infra-handoff.md`.
- **Находки.** `M/reports/`: `harness.md` LIF-10, HAR-06, § 6; `geo.md` GEO-01, GEO-05, § 4; `security.md` SEC-02,
  SEC-06…09, § 6; `contract.md` § 5, § 11; `seo.md` SEO-02, § 8. Данные хаба CrowdSec — `M/geo/dl-crowdsec/`,
  `M/geo/crowdsec-ua-match.txt`; форма адреса за Traefik — `M/p3c/edge-contract.{sh,mjs,log}`,
  `M/val-p3b/edge-probe.log`, `M/validation-seo-geo-layer-{B,C}.md` (N1, § 7).
- **Обвязка I.** `CLAUDE.md` (make-first, planning-first, границы: static-конфиг Traefik — «сначала спросить»,
  `--no-verify`, force-push, `docker volume rm`, `down -v` — никогда), `.claude/rules/*`, скилл `/plan` (форма этого
  файла), гейт `make check` = `validate` + `doctor` + `plan-check` + `project-check`; хуки ставит `make setup`.
- **Что осталось от исходной картины** (`d8458e3`, стенд — `M/p7/baseline.log`): журнал доступа — stdout, только
  статусы 400–599, без заголовков запроса; `acquis.yaml` читает `/var/log/traefik/*.log`, который никто не пишет;
  постоверфлоу в compose не заданы — `rdns` и `seo-bots-whitelist` приходят с коллекцией `crowdsecurity/traefik`;
  смок — `10-host`, `20-containers`; проза: корень — заглушка, `<org>/site` читает `fsd/<surface>/`.
- **Факты, снятые при планировании** (пробы на образах машины, без проброса портов; контейнеры проб убраны):
  - Traefik `v3.6.16`: `User-Agent: keep` даёт ключ `request_User-Agent`; на HEAD `compress` не работает.
  - CrowdSec `v1.7.7` (Alpine 3.21, entrypoint `/bin/bash /docker_start.sh`): в образе есть `crond`, `wget`, `yq`,
    `flock`, нет `curl` и `jq`; `cscli allowlists` — `create`, `add` (сети, срок `-e`, комментарий `-d`), `remove`,
    `inspect`, `check`, правится только на LAPI; постоверфлоу ставит `POSTOVERFLOWS`. Парсер `traefik-logs` берёт
    `ClientHost`, `DownstreamStatus`, `RequestPath`, `RequestHost`, `request_User-Agent`; `http-crawl-non_statics` —
    40 разных не-статических путей при утечке 0,5 с, статус не смотрит; `http-bad-user-agent` — два запроса за
    минуту, в его списке `CCBot`; частные адреса (сеть docker) до сценариев не доходят (`crowdsecurity/whitelists`).
  - Плагин bouncer `v1.4.4`, режим `live`: вердикт — и «чист», и «бан» — живёт в кеше до 60 с.
  - Реестр: печать § 1.5 — 25 строк; 20 с `ip_list_url` (18 разных адресов, `claude.com/crawling/bots.json` — общий
    для трёх ботов), `YandexBot` — только `rdns_suffix`, 4 строки без обоих полей (`meta-*`, `MistralAI-Training`).
- **Стенд** — одноразовый «VPS в контейнере», `M/p7/stand.sh` (справка — шапка скрипта): `image` — образы сайта из
  worktree `M/wt-p7-site`; `up <ревизия I>` — контейнер `p7-vps` (`docker:dind`, без проброса портов) с клоном `I` в
  `/opt/p7-infra`, registry `127.0.0.1:5000` и `.env` от `make new-env` (`DOMAIN=p7.test`, сертификат
  самоподписанный); `sync` — рабочее дерево `I` коммитом в origin стенда, в клон оно приезжает как на VPS, с `git
  pull` из `make deploy`; `down` — убрать. «На стенде `X`» = `M/exclusive.sh M/p7/stand.sh sh 'X'`; `scurl` = `curl
  -sk --resolve p7.test:443:127.0.0.1` там же. Стенд один на машину: поднял — убрал. Адрес клиента стенда частный
  (шлюз сети `proxy`): баны по сети показываются строками журнала с публичным `ClientHost` и `cscli decisions list`,
  ответ bouncer — решением `cscli decisions add` на адрес клиента. Теги registry стенда: `<тег>` = `v1.0.0` (HEAD
  `R`), `<битый>` = `v1.0.1-broken` (без `/healthz`), `<asdt>` = `v1.0.2-asdt` (`allow-search-deny-training`).
- **Гейт шага:** до коммита — `make check` в `I` → `✓ check clean` и проверка шага на стенде с рабочим деревом
  (`sync`): там `make validate` → `compose syntax PASS`. **Гейт этапа:** проверки шагов этапа на свежем стенде с
  нуля (`up <последний коммит>`, первый `make deploy`) — исполнитель и, независимо, валидатор.
- **Коммиты** — Conventional Commits `I` (`feat|fix|refactor|docs|test|chore|meta|perf`, subject ≤ 72, по-русски),
  static-конфиг Traefik — отдельным коммитом; в конце — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

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
  - Подтверждено: стенд (`M/p7/s3-check.log`): код 0 за 4 с, healthy, штамповка; `<битый>` и тег без образа — код 2
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
  - Подтверждено: стенд (`s3-check.log`): пять заголовков и `br`, лишних нет; `POST /` — 405 заглушки, четыре edge
- [x] **AC4** — Избыточный трафик получает 429, а не 403: серия POST на `/api/contact` упирается в лимит формы, и
  заявка сверх лимита до процесса не доходит; тело формы больше 64 КиБ без `Content-Length` — 413 от edge; отказ WAF
  (решение CrowdSec о бане) — тоже 429; у лимитов нет `sourceCriterion`, в цепочке формы нет `retry` и `compress`.
  Проверка: на стенде 8 POST с `Origin: https://p7.test` и незаполненной формой → пять ответов формы (200), затем
  429, ни одного 403 и 303; вне серии chunked-тело 70 КБ → 413; `cscli decisions add --ip <адрес клиента>` → через
  ≤ 60 с `/` — 429, после `decisions delete` — 200
  - Подтверждено: стенд (`s3-check.log`): серия — `200` × 5, `429` × 3, до процесса дошло 5; chunked 70 КБ — 413, до
    процесса 0; решение на адрес клиента — 429 в пределах 60 с, после `decisions delete` — 200
- [x] **AC5** — Не-прод закрыт тремя контурами и включается переменными `.env`: при `SITE_EDGE_EXTRA_MW`,
  `STAGING_BASIC_AUTH_USERS` и `ROBOTS_POLICY=noindex` `/` без пароля — 401 с `X-Robots-Tag: noindex, nofollow,
  noarchive`, с паролем — 200 с тем же заголовком, `robots.txt` сервиса — `Disallow: /`; при пустых переменных замка и
  заголовка нет; отрендеренный файл замка в git не попадает. Проверка: стенд в не-прод профиле — `scurl -I
  https://p7.test/` → 401 и заголовок, `scurl -u <пользователь>:<пароль>` → 200; `git status --short` после
  `make render` → файла замка нет; прод-профиль → 200 без `X-Robots-Tag`
  - Подтверждено: стенд (`s3-check.log`): без пароля — 401 с `X-Robots-Tag`, с паролем — 200 с ним же, `robots.txt`
    сервиса — `Disallow: /`; после `make render` файла замка в `git status` нет; прод-профиль — 200 без заголовка
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
  поломок → 12 из 12 пойманы
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
  нет, dashboard закрыт. Проверка: `make check` на чистом дереве → `✓ check clean`; на стенде `make validate` →
  `compose syntax PASS`; лог Traefik после деплоя — без ошибок, кроме ACME стенда; `grep -rn sanitizePath compose
  configs` → пусто; `grep -l docker.sock compose/*.yml` → только `compose/traefik.yml`

## Шаги
### Этап A — стенд, edge, сервис
- [x] **S1** — План фазы — в `I/.claude/plans/` (`status: in-progress`), хуки поставлены; стенд `M/p7/stand.sh`
  поднимает «VPS в контейнере» с registry и образом сайта из HEAD `R`; исходная картина на `d8458e3` записана:
  `make bump SVC=site` — отказ, источник журнала у CrowdSec пуст, у ответа заглушки `X-XSS-Protection` и нет
  `Permissions-Policy`
  - Проверка: `M/exclusive.sh M/p7/stand.sh up d8458e3` → на стенде `make ps`: `traefik`, `crowdsec`, `landing`
    healthy; `M/p7/baseline.log` — три красных факта; `stand.sh down` → `docker ps -a` без `p7-`; `make plan-check`
    → OK · Зависит от: —
  - Сделано: план и хуки (`commit-msg`, `pre-commit`) на месте; `stand.sh` и `baseline.sh` — в `M/p7/`. Свежий стенд
    `d8458e3`: первый `make deploy` — код 0, три сервиса healthy; `make bump SVC=site` — `no such service`, код 2;
    источников acquisition — 0; у заглушки `x-xss-protection: 1; mode=block`, `Permissions-Policy` нет; `down` — чисто
- [x] **S2** — Middleware edge — по § 1.3: `secure-headers` в составе списка (без XSS-фильтра и `sslRedirect`, с
  `Permissions-Policy`), `compress`, `www-to-apex`, `form-rate-limit`, `form-body-limit`, `retry`, `deny-all`, контур
  staging (`staging-noindex` перед `staging-auth`; файл замка рендерится из `.env` и не попадает в git), отказ WAF —
  429
  - Проверка: на стенде `make deploy` → лог Traefik без ошибок конфигурации; `scurl -I https://p7.test/` (заглушка)
    → четыре заголовка edge, `X-XSS-Protection` нет; решение `cscli decisions add` на адрес клиента → 429;
    `make validate` → OK · Закрывает: AC3, AC4, AC5 · Зависит от: S1
  - Сделано: `middlewares.yml.tpl` — состав § 1.3, `staging.htpasswd.tpl`, `.gitignore`, ключ в `.env.example`. Стенд
    (`M/p7/s2-check.{sh,log}`): ошибок конфигурации 0; у заглушки 4 заголовка edge, лишних 0; решение на адрес клиента
    → 429; проба каждого middleware — `br` и `gzip`, 301 на apex, 403, 413, 429, 401 с `X-Robots-Tag`; замка в git нет
- [x] **S3** — Сервис `site` в стеке и выкатка: `compose/site.yml` по § 1.1 (профиль `site`; роутеры `site`,
  `site-form`, `site-image`, `site-www`; healthcheck контейнера и сервиса Traefik), секция `profile site` в
  `.env.example` и подсказки `make new-env`, `site` в роли `edge`, `www` в DNS-preflight, `make bump` ждёт healthy
  - Проверка: на стенде `make bump SVC=site TAG=<тег>` → код 0, `site` healthy, строка штамповки; `TAG=<битый>` →
    код ≠ 0; curl-строки § 1.7 п. 4, 5, 7, 8 (адрес, методы, `/_image`, `www`, заголовки, серия POST, не-прод
    профиль); `HOST_ROLE=edge` → `make deploy` поднимает `site`; DNS-preflight при профиле `site` называет
    `www.p7.test`; `make validate` → `compose syntax PASS`, `.env coverage PASS` · Закрывает: AC1, AC2, AC3, AC4, AC5
    · Зависит от: S2
  - Сделано: `compose/site.yml`, секция `profile site` и подсказки `new-env`, `ROLE_FILES[edge]`, `www` в preflight,
    `bump` с `--wait --wait-timeout 90`, рендер без перезаписи неизменённого файла, строки прозы и правил о составе
    стека. Стенд `331dd9c` с рабочим деревом (`M/p7/s3-check.{sh,log}`): 88 проверок, расхождений 0 — выкатка, адрес,
    методы, `/_image`, `www`, заголовки, форма, WAF, не-прод и обратно, `HOST_ROLE=edge`, `validate`, `doctor`

### Этап B — журнал и CrowdSec
- [ ] **S4** — Журнал доступа — файл `/var/log/traefik/access.log`: JSON, все статусы, `User-Agent` и
  `X-Request-Id`; ротация — в стеке (static-конфиг Traefik — отдельным коммитом)
  - Проверка: на стенде запрос с UA бота → последняя запись журнала: `DownstreamStatus` 200 и `request_User-Agent`;
    `X-Request-Id` ответа `/net-takogo` — в записи журнала и в `make logs SVC=site`; запуск ротации → активный файл
    сброшен, следующая запись — в нём · Закрывает: AC6 · Зависит от: S3
- [ ] **S5** — CrowdSec читает журнал и бережёт поисковиков: источник acquisition непуст с первого деплоя чистого
  стенда; постоверфлоу `rdns` и `seo-bots-whitelist` установлены; сценарии обхода срабатывают на постороннем адресе
  - Проверка: свежий стенд → `make deploy` → `cscli metrics show acquisition` — строк источника журнала > 0;
    `cscli postoverflows list` → оба; 45 строк журнала с `ClientHost: 203.0.113.7` и разными путями → в
    `cscli decisions list` решение; запись после ротации журнала читается · Закрывает: AC6, AC7 · Зависит от: S4
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
- Журнал — файл в каталоге хоста `/var/log/traefik`, не docker-источник (из двух вариантов контракта — A):
  `acquis.yaml` и монтирование `/var/log` у `crowdsec` уже рассчитаны на этот путь, он же верен буквально в § 1.4 и
  в отчёте сайта «бот × статус»; docker-сокет второму контейнеру — расширение прав того, кто разбирает чужой ввод.
- Расписание (ротация журнала, обновление allowlist) живёт в стеке, как cron бэкапа, а не на хосте: host-cron шаблон
  не держит, правка доезжает `make deploy` без перепрогона ansible и проверяется на стенде. Где именно крутится
  `crond` (контейнер `crowdsec` или спутник в `compose/crowdsec.yml`) — выбор исполнителя по фактам образа.
- Отказ WAF — 429 (`remediationStatusCode` плагина): лимит формы и сайта стоит выше порога сценария обхода и бота
  без списка вендора от бана не спасает; 429 для него и для ложного срабатывания — «приходи позже», а не «страницы
  нет». Защита не слабее: запрос так же не доходит до сервиса.
- Порядок контура staging — `staging-noindex`, затем `staging-auth`: иначе ответ 401 уходит без `X-Robots-Tag`
  (факт Traefik `v3.6.16`). Значение переменной — `,staging-noindex@file,staging-auth@file`.
- Смена пароля замка staging — `make deploy` и `make restart SVC=traefik`: `usersFile` Traefik читает при сборке
  цепочки (стенд: старый пароль жив до рестарта); строка — в `.env.example`, в правило `secrets-and-env` — S9. Хеш —
  bcrypt как самый стойкий; `$apr1$…` envsubst не портит, ловушка значения одна — кавычки в `.env` (Р15, Р17).
- Отказ тела сверх лимита Traefik пишет в лог уровнем `ERR` (`vulcand/oxy/buffer`): это ответ 413, а не ошибка
  конфигурации — проверка «лог без ошибок» (AC11) такие строки не считает.
- Healthcheck `site` — с `start_interval: 1s`: роутеры контейнера в состоянии `starting` docker-провайдер Traefik не
  строит, и при пересоздании ~5 с отвечала заглушка (стенд; стало ~2 с, `bump` — 2 с вместо 6). Нужен Docker ≥ 25.
  Остаток окна в 503 превращает `providers.docker.allowEmptyServices` (static-конфиг) — на усмотрение S4 (Р18).
- `render-configs.sh` не перезаписывает неизменённый файл: файл `dynamic`, прочитанный watcher'ом Traefik посреди
  записи, оставлял роутеры без middleware (стенд: ошибка разбора на 30 рендеров; после правки — 0).
- Первый разворот: профиль `site` в `.env`, затем `make bump` (ставит `SITE_TAG`); профиль без тега роняет
  `make deploy` (`invalid reference format`), `bump` без профиля поднимает сервис мимо `make deploy`.
- Политику сайта задание allowlist читает с `robots.txt` сервиса напрямую (`site:3000`), не через публичный адрес:
  на не-прод тот отвечает 401, на стенде домена нет. Нет сервиса `site` или ответа — allowlist не меняется.
- Список источников — файл хаба из печати контракта, а не копия реестра: пересборка — команда хаба, вызывающая
  печать в соседнем `<org>/site`; общий список трёх ботов Anthropic идёт в allowlist, пока политика пускает хотя бы
  одного из них, — по адресу их не различить. Сеть шире порога (исполнитель S6) отвергается: чужой ответ не открывает
  edge. Записи allowlist живут со сроком — сеть, которую вендор убрал, уходит сама.
- Локальная rDNS-страховка не делается: суффиксы Яндекса несёт `seo-bots-whitelist` хаба CrowdSec, своя копия —
  рукописный дубль.
- Заглушка `landing` остаётся always-on шаблона и держит выпуск сертификата корня до первого деплоя сайта; при сайте
  на корне её прунит `/de-template` (вариант контракта). Профиль памяти — 512 МБ и `--max-old-space-size=384`,
  staging — переменной `.env` (предложения контракта).
- Правка static-конфига Traefik и контракта `.env.example` — граница «сначала спросить» обвязки `I`; основание —
  строка фазы P7 программы, принятой владельцем («`User-Agent` в access-log»), и § 1.4 контракта.
- Имя сервиса `site` — умолчание шаблона и поле `infra-svc` форка; поверхность с другим именем (strategy: имя сервиса
  — slug поверхности) заводит `/add-service` по тому же варианту.
- Канон «кто что читает из strategy» пишется по контракту strategy 0.2.0 (R01): слой страницы, пакет дизайна,
  `ready.yaml`. Документы `R` догоняют его в P8.
- Приёмка § 1.7 — верб хаба, а не чек-лист в соседнем репо: страницу для проверок формы адреса берёт из
  `sitemap.xml` сайта (у форка нет `/about`), UA — из токенов `ai-bots.sources`.
- Приёмка фазы — на стенде шаблона: прогон `make accept SVC=site` на живом VPS с доменом до закрытия фазы не
  нужен (решение владельца); сертификаты apex и `www` и настоящие адреса ботов — приёмка первого деплоя проекта.
- Стенд — «VPS в контейнере», а не compose на машине: имена контейнеров и сетей шаблона фиксированы, а на машине
  работают чужие контейнеры; registry стенда даёт настоящий pull. `make deploy` и `.env` живут в клоне стенда — в
  дереве `I` файл `.env` не появляется (он переключает ops-вербы на локальный docker).

## Handoff
- Репо сайта (через дирижёра): расхождения и уточнения контракта — § 3 файла покрытия.
- Оператору форка: секция `profile site` в `.env` (тег, канал формы, на не-прод — три переменные staging), DNS-запись
  `www`, Docker Engine ≥ 25 на VPS, после первого деплоя — `make accept SVC=site`. Обновление действующего VPS:
  `make deploy` рестартует Traefik (static-конфиг) — секунды простоя; с полным журналом сценарии обхода CrowdSec
  начинают работать — свой аудит с рабочей станции может получить 429 (runbook).
- Бэклог `I` (не тема фазы): `make validate` без `.env` не разбирает compose и не ловит `:latest`, хотя проза это
  обещает; источник `auth.log` у CrowdSec пуст на Debian 12 без rsyslog; `configs/landing/index.html` не в
  `.gitignore`; `deploy.sh` глотает отказ `git pull --ff-only`; `make new-env` не пишет `HOST_ROLE` — WARN `doctor`.

## Где мы сейчас
Этап A закрыт: S1–S3 сделаны, AC1 и AC3–AC5 подтверждены. Гейт этапа — свежий стенд с нуля на `6cfd4a6`
(`M/p7/stage-a.sh`, логи `M/p7/stage-a*.log`): S2 — ошибок конфигурации 0, S3 — 92 проверки, расхождений 0; дренаж
`docker stop site` — код 0 за 0,2 с. Дальше — независимый валидатор этапа A, затем S4 (этап B): журнал доступа —
файл с `User-Agent`, ротация в стеке, static-конфиг отдельным коммитом.
