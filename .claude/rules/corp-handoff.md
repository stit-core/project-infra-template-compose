---
description: Изменение corp-поверхности (новая Vault-KV-зависимость / профиль / env-контракт / crowdsec-whitelist / новый env-онбординг / новый сабдомен под LE) ОБЯЗАНО породить CORP-HANDOFF-блок корп-админу (или DNS-владельцу) до claim «готово». Грузится при правке configs/vault-agent, compose-профилей, .env.example, crowdsec whitelists, ansible onboard.
paths:
  - "configs/vault-agent/**"
  - "compose/*.yml"
  - ".env.example"
  - "configs/crowdsec/whitelists.yaml"
  - "ansible/roles/stit-onboard/**"
---

# Corp-handoff

Этот репо **и есть** таргет деплоя (`ship → deploy → контейнер`). Но часть
конфига живёт не здесь, а на корп-стороне: Vault (`kv/projects/<p>/<env>/*`),
AppRole/онбординг, CrowdSec-whitelist, OTLP-tenant. Любое изменение, которое
**требует действия корп-стороны** (или владельца DNS), обязано быть зафиксировано
явно — иначе стек молча не поднимется (vault-agent retry-loop / cert не выпишется).

**Железобетонное правило:** тронул corp-поверхность → до claim «готово» / до
коммита оформи `CORP-HANDOFF`-блок и **попроси оператора передать его корп-админу**
(out-of-band: Slack / тикет / PR в `stit-infra/infra`). Не молчи, не «потом».
Это soft-механизм (правило + skill, не хук) — единственная гарантия в том, что
ты его исполняешь.

## Что считается corp-поверхностью

| Класс | Триггер | Кому |
|---|---|---|
| **Vault KV** | новый профиль в `COMPOSE_PROFILES` / новый сервис, которому нужен KV-объект (`db`/`oidc`/`jwt`/`minio`/`backup`/project-specific); новое поле в существующем объекте; новый `${VAR}` из vault-agent template | корп (Vault) — через skill `request-secret` |
| **Env-онбординг** | новый `ENV`/проект (новый VPS) — нужен AppRole `projects-<p>-<env>` + seed `meta`+`otel` | корп (`onboard-project.sh --envs`) |
| **CrowdSec whitelist** | новый egress-IP проектной VPS (иначе otel-collector UA ловит `http-bad-user-agent`, метрики режутся 403) | корп (`whitelists.yaml` + crowdsec restart) |
| **DNS** | новый сабдомен `<name>.${DOMAIN}` под LE HTTP-01 | владелец DNS (A-record `*.${DOMAIN}` → VPS IP) |

Не-corp: чисто локальная правка (compose-логика без нового KV/профиля, .tpl-рефактор
без нового `${VAR}`, scripts/tools, доки, healthcheck-тюнинг).

## Формат CORP-HANDOFF-блока

```
=== CORP HANDOFF · передай корп-админу ===
WHAT   <что изменилось: имя объекта/поля/профиля/IP, required?>
WHY    <фича/причина — ссылка на коммит/план-атом>
ACTION <что корп обязан сделать: vault kv put/patch <path> / onboard-project --envs / whitelist IP / DNS A-record>
WHO    <корп (Vault/AppRole/CrowdSec/OTLP) | владелец DNS>
DECIDE <нужно ли решение: значение/выбор; или «дефолт N годится?»>
RISK   <что будет, если не сделано: стек не поднимется / cert не выпишется / метрики режутся>
===
```

## Куда кладётся (чтобы доехало)

1. **В чат** — покажи блок оператору с явным «передай корп-админу out-of-band».
2. **В активный план** — подсекция `**Corp impact.**` активной `### `-секции в `.claude/plans/roadmap.md`.
   `scripts/ship.sh` агрегирует её перед push. План forward-only и удаляется
   по закрытии — поэтому corp-impact обязан доехать до корп-стороны **до**
   закрытия плана (см. skill `plan` §8).

Нет активного плана (мелкая прямая правка) — блок только в чат; проследи, что
оператор зафиксировал передачу.

## Делать

- Оформлять блок **до** claim «готово»/коммита, не после.
- Один блок на одно логически цельное corp-изменение; несколько — список в `## Corp impact`.
- Конкретика: точный KV-path, имя поля, required-флаг, точное действие. «Что-то с Vault» — бесполезно админу.
- Для seed/patch KV — делегируй skill `request-secret` (он печатает готовый `vault kv put`-блок).

## Не делать

- ❌ Молча закоммитить новый профиль / KV-зависимость / `${VAR}` из template без блока.
- ❌ Откладывать «на ship» — ship агрегирует уже **записанное** в `## Corp impact`; не записал → потерял.
- ❌ Самому выполнять `vault kv put`/`patch` / `ssh` на корп-VPS — не зона этого репо.
- ❌ Писать значение секрета в блок/чат — только имя пути/поля и факт «нужен» (см. `.claude/rules/secrets-and-env.md`).
- ❌ Workaround'ить отсутствующий KV/политику обходом вместо handoff (см. skill `triage`).
- ❌ Помечать задачу «готово», пока handoff не предъявлен оператору.

## Сигналы, что ты здесь

- `make status` → `== Infra-touch ==` ≠ none (cockpit `smartdev` чейнит сюда).
- Правишь файл под `paths:` этого правила (оно само в контексте).
- `make ship` напомнил, что `## Corp impact` пуст при тронутой corp-поверхности.

Процедура — skill `corp-handoff`. Seed конкретного KV — skill `request-secret` (его частный случай).
