# Документация

Роутер по docs. Три аудитории + design source-of-truth.

## Потребителю шаблона
- [getting-started.md](getting-started.md) — путь от форка до работающей проектной VPS:
  доступ к registry → bootstrap нового VPS → первый деплой → активация профилей →
  `/init-project` → своя инфра. **[META]** — удаляется при де-темплейтизации.

## Контрибьютору шаблона
- [contributing.md](contributing.md) — как устроена `.claude`-система (rules/skills/agents/
  settings), что enforce'ится, как вмешаться, troubleshooting. **[META]**.

## Reference (переезжает в проект)
- [reference/architecture.md](reference/architecture.md) — слои, сети, профили, поток секретов,
  deploy-флоу, что НЕ в шаблоне.
- [reference/ecosystem.md](reference/ecosystem.md) — канон экосистемы: карта репо, операционный флоу,
  резолв сиблингов, кто что читает из `<org>/strategy`, контракт сервис-репо ↔ хаб.
- [reference/project-root.md](reference/project-root.md) — корень проекта `~/git/<org>/`: карта проекта
  `CLAUDE.md`, общие настройки сессии, `local/`, как сессия корня видит репо; образцы файлов корня.
- [reference/runbook.md](reference/runbook.md) — failure modes на проектном VPS, recovery, DR-drill.

## Infra design source-of-truth
- `docs/project/` — инфра-артефакты (`stack.md` с картой сервисов + `services/<name>.md`), вход
  для `/init-project` и `/de-template`. Контракт — `docs/project/README.md`.
- Продуктовый контекст (vision / surfaces) — в соседнем `<org>/strategy` (форк `business-strategy-template`),
  читается cross-repo; конвенция размещения — `docs/reference/ecosystem.md`.

Точка входа агента в репо — `CLAUDE.md` (ядро + роутер). Дневной флоу — skill `/smartdev`.
