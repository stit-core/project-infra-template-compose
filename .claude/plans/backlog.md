# Backlog

Кандидаты в работу, ещё не взятые в план: `- **<id>** — что и зачем. Триггер: когда браться.` Форма и жизненный цикл — skill `/plan`.

- **ipv6-edge** — AAAA — только с `ip6tables` и без `userland-proxy`; иначе IPv6-клиент приходит в Traefik с адреса
  шлюза `proxy`: CrowdSec его не банит, лимиты общие. Триггер: домену нужна AAAA.
- **crowdsec-start-offline** — entrypoint образа CrowdSec на каждом старте ставит парсеры и коллекции через `cscli`, а
  тот сверяет версию с `version.crowdsec.net`: без выхода наружу рестарт `crowdsec` — петля рестартов, и bouncer
  отвечает 429 каждому новому клиенту (runbook называет 6–8 с). Триггер: VPS с закрытым выходом наружу или рестарт
  CrowdSec, сорвавшийся на хабе.
- **bouncer-plugin-start** — плагин bouncer Traefik качает при каждом старте: без сети edge закрыт до её возврата
  (`abortOnPluginFailure`); версию закрепляет тег, хеш плагина (`hash`) не задан. Триггер: старт Traefik, сорвавшийся
  на загрузке плагина, или бамп плагина.
- **smoke-journal-empty** — у пустого журнала (сразу после ротации, до первого запроса) смок печатает «первая запись —
  N ч назад»: `date -d ""` — полночь; `ATTENTION` от этого не ложный (порог 26 ч больше суток). Триггер: правка
  `scripts/tools/smoke.d/30-edge.sh`.
- **landing-start-interval** — заглушка после пересоздания до первой пробы здоровья (интервал 30 с, без
  `start_interval`) отвечает 500 от edge. Триггер: форк без сайта, у которого корень — заглушка.
- **validate-latest** — `:latest` не ловит ни одна проверка, хотя `CLAUDE.md` называет `make validate`; без `.env`
  `compose syntax` — SKIP. Триггер: правка `scripts/tools/validate.sh`.
- **edge-defaults-file** — статика `edge defaults` не читает роутеры file-провайдера (`configs/traefik/dynamic/`):
  роутер без `crowdsec@file` или без `Host` там пройдёт гейт. Триггер: первый роутер в file-провайдере.
- **deploy-pull-fail** — `make deploy` продолжает на прежней ревизии, когда `git pull --ff-only` отказал, без строки
  `ERR`. Триггер: правка `scripts/deploy.sh`.
- **traefik-api-local** — API Traefik не отвечает и изнутри контейнера (`/api/*` — 404): роутеры разбираются по логу
  Traefik и labels. Триггер: диагностика, которой нужен `rawdata`.
- **crowdsec-sshd-journald** — сценарии sshd CrowdSec слепы на Debian 12 без rsyslog: `/var/log/auth.log` нет, журнал —
  journald. Триггер: VPS на Debian 12+ или защита SSH CrowdSec'ом.
