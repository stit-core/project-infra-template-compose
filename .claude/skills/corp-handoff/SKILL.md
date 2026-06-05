---
name: corp-handoff
description: Оформить CORP-HANDOFF-блок, когда изменение требует действия корп-стороны (Vault seed/patch, новый AppRole/env-онбординг, CrowdSec-whitelist egress-IP, новый сабдомен под LE-DNS). smartdev чейнит сюда на `== Infra-touch ==` ≠ none. Активируй когда правишь configs/vault-agent / compose-профиль / .env.example / crowdsec whitelist / ansible-onboard, или юзер пишет «нужен seed», «передать корп», «что отдать админу». Seed конкретного KV — частный случай, делегируй skill request-secret.
---

# Skill: corp-handoff

Зафиксировать явно то, что без действия корп-стороны молча разъедется с прод-
окружением. Контракт и классификация — `.claude/rules/corp-handoff.md` (грузится
автоматически при правке corp-поверхности).

## Когда применять

- `make status` → `== Infra-touch ==` ≠ none (smartdev чейнит сюда)
- Правишь `configs/vault-agent/` (`agent.hcl.parts/`, `templates/`),
  добавляешь профиль в `COMPOSE_PROFILES`/`compose/*.yml`, новый `${VAR}` в
  `.env.example`, `ansible/roles/sftbmb-onboard/`, либо нужен CrowdSec-whitelist
  egress-IP корп-side (файл в `corp-infra-template`, не здесь)
- Юзер: «нужен seed для X», «что передать корп-админу», «новый env/VPS»

## Когда НЕ применять

- Чисто локальная правка без нового KV/профиля/IP/сабдомена — не corp-поверхность
- Падение из-за уже-нужного-но-несозданного KV → сначала `triage` (диагноз), он направит сюда

## Шаги

### 1. Классифицировать

По таблице из `.claude/rules/corp-handoff.md`: **Vault KV** / **Env-онбординг** /
**CrowdSec whitelist** / **DNS**. Один логически цельный пункт = один блок;
несколько — список.

### 2. Определить адресата

- Vault KV / AppRole / OTLP / CrowdSec → **корп-админ** (`corp-infra-template`).
- Новый сабдомен под LE → **владелец DNS** (A-record `*.${DOMAIN}` → VPS IP).

### 3. Сформировать блок

```
=== CORP HANDOFF · передай корп-админу ===
WHAT   <имя объекта/поля/профиля/IP, required?>
WHY    <причина — коммит/план-атом>
ACTION <vault kv put/patch <path> | onboard-project --envs <env> | whitelist <IP> | DNS A <host>→<IP>>
WHO    <корп | владелец DNS>
DECIDE <значение/выбор нужен, или «дефолт годится?»>
RISK   <стек не поднимется / cert не выпишется / метрики 403>
===
```

Только имя пути/поля и факт «нужен» — **никогда значение секрета** в блок/чат
(`.claude/rules/secrets-and-env.md`).

### 4. Для seed/patch конкретного KV — делегируй `request-secret`

Если ACTION = создать/пропатчить `kv/projects/<p>/<env>/<name>` — переключись в
skill `request-secret`: он выяснит поля, сгенерит случайные пароли где надо и
напечатает готовый `vault kv put`-блок для копи-паста корп-админу. `request-secret`
— частный случай corp-handoff (seed). Остальные классы (онбординг/whitelist/DNS)
оформляются блоком здесь.

### 5. Положить так, чтобы доехало

- **В чат** — покажи блок оператору: «передай корп-админу out-of-band (Slack/тикет/PR)».
- **Активный план есть** → допиши айтем в `**Corp impact.**` активной `### `-секции в `.claude/plans/roadmap.md`.
  `scripts/ship.sh` агрегирует секцию перед push. План удаляется по закрытии —
  значит айтем обязан доехать до корп-стороны **до** закрытия (skill `plan` §8):
  либо `make ship` его сагрегировал и оператор передал, либо follow-up строкой
  в `roadmap.md ## Backlog`.
- Нет плана (мелкая правка) → блок только в чат; проследи фиксацию передачи.

### 6. Не помечай «готово», пока блок не предъявлен

Claim «готово» при тронутой corp-поверхности без предъявленного блока — нарушение
правила. После seed'а корп-стороной vault-agent подхватит на следующем render-
цикле; на чистом дереве `make ship` без MSG триггерит force-recreate consumer'ов.

## Anti-patterns

- ❌ Молча закоммитить профиль/KV-зависимость/`${VAR}` без блока.
- ❌ «Оформлю на ship» — ship агрегирует уже записанное; не записал → потерял.
- ❌ Значение секрета в блоке/чате.
- ❌ Самому `vault kv put`/`ssh` на корп — не зона этого репо.
- ❌ Обойти отсутствующий KV workaround'ом вместо handoff.
