# Контракт `draft → stable` — stack-deep-dive

Запись становится `stable`, когда **все 7 пунктов одновременно** ✅.
Скилл проверяет, архитектор подтверждает, скилл применяет.

## Чек-лист

### 1. Frontmatter валиден

- `id == "project.stack"`.
- `kind == "stack"`.
- `name == "stack"`.
- `status` ∈ {`draft`, `stable`}.

Программная проверка — `make project-check A=docs/project/stack.md`.

### 2. Все 6 H2 присутствуют и непусты

- `## Domains`, `## Edge`, `## Networks`, `## Backup`,
  `## Observability`, `## Generates`.
- Placeholder `<...>` (как в `_templates/stack.md`) **не считается**
  содержимым.
- `N/A` явной строкой — допустимо для `Backup` (если нет
  storage/postgres в карте) и для прочих секций, где это объяснимо.
- Программно проверяется тем же валидатором при `status: stable`.

См. `field-checklists.md § <section>` — что считается «непустым» по
каждой секции.

### 3. Все ссылки валидны

| ссылка | где | как проверить |
|---|---|---|
| сабдомены | `Domains` | каждый сабдомен упомянут в каком-то `services/*.md § Route` ИЛИ явный stub-next-step |
| public-сервисы из карты | `Domains` | каждый `Route: <sub>` имеет соответствующий пункт в `Domains` ИЛИ open-question в state |
| имена сетей | `Networks` | соответствуют тому, что есть в `compose/` (или явный rename-план в `Generates`) |
| `Backup: N/A` ↔ карта | `Backup` | в карте нет `datastore` И нет volume'ов под бэкап |
| `Generates` пути | `Generates` | реалистичны (`configs/traefik/dynamic/*`, `.env.example`, `configs/crowdsec/whitelists.yaml`) |
| `acme_email`/`acme_caserver` | `Domains` / `Generates` | значения отмечены как next-step через `meta` KV (corp-handoff) |

### 4. `Generates` содержит хотя бы один реальный артефакт

`stack § Generates` — вход для `/de-template`. Должен содержать
**минимум один** из:

- `configs/traefik/dynamic/*` (динамические роуты),
- `DOMAIN` в `.env.example` (либо проектный default),
- crowdsec source-IP next-step (corp-handoff),
- acme `meta` next-step (для `meta.acme_email`/`acme_caserver`).

Если ни одного — `Generates` бесполезен, `/de-template` не из чего
разворачивать. Это блокер.

**НЕ должно быть** в `Generates`:

- `COMPOSE_PROFILES=...` целиком — выводится из карты сервисов
  движком `/de-template`, не из stack;
- описание always-on фундамента («traefik будет запущен») — не
  Generates, фундамент есть всегда;
- service-specific traefik labels — они в service-doc `Generates`.

### 5. Тест-критерий явно подтверждён

В `field-checklists.md § Глобальный Тест-критерий kind=stack` есть
2 опции ✅/❌. Через `AskUserQuestion` скилл предъявляет, архитектор
подтверждает.

### 6. State-заметка чиста по `**blocker**`-вопросам

`state/stack.md`:

- Не содержит секцию `## Открытые вопросы` ИЛИ
- Содержит, но в ней нет `**blocker**`-вопросов.

Не-blocker открытые вопросы при stable допустимы (например, «retention
уточнить с заказчиком — не блокирует, дефолт 7d»). Секция `## Доменные
решения` к stable не относится — может быть. Секция `## Что копать
дальше` — обычно пуста.

### 7. `make project-check` зелёный

Финальный программный gate.

## Алгоритм проверки скиллом

После любой правки секции:

1. Прочитать `stack.md`.
2. Прочитать `state/stack.md`, если есть.
3. Прогнать пункты 1, 2, 3, 4, 6, 7 (программно проверяемые).
4. Если все 6 ✅ — раунд `AskUserQuestion` по тест-критерию (пункт 5).
5. Если и пункт 5 ✅ — раунд `AskUserQuestion`: «Готов к stable,
   повышаем?» с опциями «Да, повысить» / «Нет, ещё не уверен» (через
   Other — что именно смущает).
6. При «Да» — Edit'ом поменять `status: draft → stable`.
7. После повышения — ещё раз `make project-check` (теперь проверит
   non-empty bodies строго).

## Что НЕ делать

- **Не повышать сам**, без подтверждения архитектора. Даже если все 7
  пунктов ✅ — спросить.
- **Не понижать `stable → draft` сам** при обнаружении проблемы.
- **Не считать пункт 5 пройденным «по умолчанию»**, потому что секции
  заполнены. Тест-критерий — отдельное смысловое подтверждение.
- **Не игнорировать `**blocker**`-вопросы**.
- **Не игнорировать рассинхрон с картой и service-doc'ами** (п.3) —
  это видимый дрейф, который сломает `/de-template`.
- **Не помечать `Backup: N/A` без проверки карты** — если в карте
  есть `datastore`, `N/A` запрещён.
