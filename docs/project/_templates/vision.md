---
id: project.vision
kind: vision
name: vision
status: draft
---

# Vision — продукт <project>

## Problem
<Какую задачу клиента решает продукт. Одно-два предложения по сути, без маркетинга.
Что считаем успехом.>

## Users
<Кто пользователи / акторы (end-user, оператор, внешняя система-интегратор). Ожидаемая
нагрузка/масштаб в первом приближении — влияет на ёмкость VPS.>

## Service map
<Авторитетный перечень всех частей продукта. Сервис с hosting: here крутится контейнером в
этом репо и получает docs/project/services/<name>.md; external — только строка контекста.>

| name | subtype | hosting | repo / source | назначение |
|---|---|---|---|---|
| backend | backend | here | `<org>/backend` (форк go-backend-template) | API |
| db | datastore | here | — (postgres в этом репо) | Postgres 17 |
| storage | datastore | here | — (minio в этом репо) | S3 + Console |
| web | frontend | external | `<org>/frontend` (CDN) | SPA |

## Boundaries
<Что в скоупе продукта и что НЕ в скоупе (явные non-goals). Где проходит граница между этим
VPS и внешними частями/корп-инфрой.>

## Environments
<Какие среды у проекта (dev/staging/prod) — каждая = отдельный VPS с одним ENV. Чем отличаются
(домен, масштаб, какие сервисы включены).>
