# Roadmap

Индекс активных и плановых задач шаблона. Per-task детальный план — `<slug>.md` в этой же директории.

По завершении задачи её план удаляется сразу, история остаётся в `git log`. Roadmap не держит секцию завершённого. Незакрытый follow-up из закрытой задачи переезжает строкой в `## Активные`, а не остаётся хвостом в удаляемом плане.

## Активные

- [in-progress] [`agent-workflow-rebuild`](./agent-workflow-rebuild.md) — перенос ребилда workflow из go-backend df59179c40 (make-словарь, cockpit smartdev, plan/triage/corp-handoff). 3 фазы, 15 атомов, 14/15 (Phase 1-2 ✓, A11-A14 ✓).
- [planning] `DOMAIN` в Vault — перенести из `.env` в `kv/projects/<p>/<env>/meta`; требует рендера `compose.env` через vault-agent и перестройки порядка в `scripts/deploy.sh`.
- [planning] `CROWDSEC_BOUNCER_API_KEY` auto-register с post-seed в Vault — требует write-token у оператора.
- [planning] Webhook от vault-agent при KV-change → авто-deploy без ручного `make ship` (корп-side).

## Планируется

(none)

---

**Формат:** `- [<status>] <slug> — <одна строка>`. Status: `planning`, `in-progress`, `blocked`.
