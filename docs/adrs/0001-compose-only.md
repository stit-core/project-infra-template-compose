# ADR 0001 — Compose-only, no k3s for V1

**Status:** accepted
**Date:** 2026-05-10

## Context

Проектная инфра должна разворачиваться за день и поддерживаться оператором без специализированного DevOps. Стейк — клиентские проекты, обычно single-region, single-host, RAM 2-8 GB.

Альтернативы:
- **docker-compose** на одном VPS.
- **k3s** (lightweight Kubernetes) на одном VPS или мини-кластере.
- **Nomad** + Consul.

## Decision

Используем docker-compose. K3s/Nomad — отдельный план если когда-нибудь, не сейчас.

## Why

- **Knowledge cost:** оператор должен дебажить «что не так с PG» в 3 утра. Compose log → docker exec → pg_isready — один-два шага. K8s — pod logs → kubectl exec → describe → events → controllers, серия сущностей которые нужно держать в голове.
- **No HA в требованиях:** клиентские проекты single-tenant, single-region. Если VPS падает — Lambda/Vercel-style autoscale не нужен; нужен restic + готовая ansible-playbook на новый VPS.
- **Compose покрывает 95% потребностей:** named volumes, networks, healthchecks, depends_on with `service_healthy`, env_file. Service mesh, autoscaling, declarative configmaps — не нужны.
- **K3s overhead:** ~512 MB RAM на control plane даже на single-node. На 2 GB VPS это 25%.
- **Migration path остаётся:** compose → kompose → manifests если когда-нибудь захочется. Обратное (k8s → compose) болезненнее.

## Consequences

- Все сервисы как docker-compose сервисы. Один файл = один сервис в `compose/`.
- Healthchecks обязательны — это единственный механизм координации запуска.
- Backup стратегия — restic на volumes, не PV snapshots.
- Без HA: если VPS падает, downtime = время на bootstrap нового VPS + restore (~15 мин при готовом ansible).

## Когда пересмотреть

- Любой проект перерастает 1 VPS (нужен read-replica PG, отдельный worker tier, multi-region).
- Compliance требует declarative manifests + RBAC изоляцию (k8s namespaces).
- Команда устала от bash-скриптов и хочет helm-charts.

До тех пор — compose.
