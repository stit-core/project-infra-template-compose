# Roadmap

Единственный артефакт планирования шаблона — этот файл. Подпапок, `<slug>.md`,
архивов и changelog'ов нет: они расходятся с правдой и мешают.

**Planning-first.** Изменение идёт через план — `### <slug>`-секцию под `## Active` ниже.
Прямая правка без плана допустима только для truly-atomic (опечатка, один очевидный файл)
и багфиксов (→ skill `triage`, RED-first). Отклонение от плана — осознанное, проговаривается
с юзером.

**Жизненный цикл.** `planning → in-progress → blocked? → done`. По `done` секция задачи
удаляется целиком — история остаётся в `git log`. Незакрытый follow-up переезжает в `## Backlog`
или новой `### `-секцией, а не хвостом в удаляемой.

**Где это запускается.** Репо живёт на машине оператора — authoring / validate / plan /
ship-поверхность. Приложения и живого стека локально нет: они на удалённом VPS. `make ship`
пушит и триггерит remote `deploy.sh` по ssh; live-ops (`ps`/`logs`/`restart`/`backup`/
`restore-pg`) прозрачно оборачивают ssh на VPS (connection из `.env.local`). Локальный SKIP
в authoring-проверках без `.env`/docker — норма, не падение.

**Current focus:** — (нет активных планов)

## Active

## Backlog
- **Corp: канон ecosystem.md под `<org>/strategy`.** `corp-infra-template/docs/ecosystem.md`
  всё ещё описывает продуктового соседа как `project-docs-template` / `<org>/docs` («DDD-артефакты»).
  Реальность: `business-strategy-template` → форк `<org>/strategy` (бизнес-стратегия + опц. продукт
  `docs/projects/<slug>/`). Правится на корп-стороне (другой репо, corp-surface, свой ревью) —
  оформлено CORP-HANDOFF-нотой оператору.
- **smoke-пороги в `.env.local`.** Серверный смок (`smoke.d/10-host.sh`) уже читает env-override
  `SMOKE_LOAD_FACTOR` / `SMOKE_RAM_MIN_PCT` / `SMOKE_DISK_PCT` (дефолты в коде). Если понадобится
  per-VPS тюнинг — добавить их в `.env.local.example` + прокинуть через `ssh.sh smoke`. Опционально,
  low-priority (дефолты годятся).
- **Corp: backport validate-plan.sh dep-check fix.** Эталонный `go-backend-template/scripts/tools/`
  `validate-plan.sh` проверяет `kk[2]` (cur, всегда валиден) вместо `kk[3]` (dep) — мёртвая
  dep-integrity проверка; здесь пофикшено при порте. Бэкпортнуть в go-backend при следующем
  касании. Latent, low-risk.
