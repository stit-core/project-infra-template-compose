---
id: project.<name>
kind: service
subtype: <backend|frontend|datastore|infra>
hosting: <here|external>
name: <name>
status: draft
---

# Service — <name>

## Hosting
<here — контейнер в этом репо (compose/<name>.yml, профиль); external — свой репо/CDN, здесь
только роут/контекст. Для backend: source-репо внешний, НО контейнер хостится here
(hosting: here, образ из git.stit.tech/<org>/backend). Какой профиль COMPOSE_PROFILES активирует.>

## Identity
<Что это: образ (`git.stit.tech/<org>/<name>:<tag>`, закреплённая версия) или движок
(postgres 17 / minio). container_name, healthcheck (path/команда), сети (proxy / backend-net).>

## Secrets
<Какой Vault KV нужен: kv/projects/<p>/<env>/<kind> и поля (db: user/password/database;
minio: root_user/...). Какой vault-agent template рендерит env. `N/A` если секретов нет.>

## Route
<Публичный ли: сабдомен (`<name>.${DOMAIN}`), traefik router + crowdsec@file middleware. Или
internal (только backend-net) → `_internal_`. Порт.>

## Generates
<Что de-template родит/изменит в инфре из этого артефакта:
- COMPOSE_PROFILES += <profile> (выводится из subtype)
- compose/<name>.yml — keep, остальные неиспользуемые pruned
- vault-agent agent.hcl.parts/<part>.hcl + templates/<kind>.env.tpl — keep
- traefik labels / dynamic route (если public)
- для external: cross-repo next-step (форкни <repo>, запиши tag в meta)>
