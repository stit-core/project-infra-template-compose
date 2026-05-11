# Non-secret конфиг проекта. Рендерится в .runtime/env/compose.env и
# подключается compose'ом через --env-file (Makefile COMPOSE_ARGS).
# Поля выставляет корп-сторона при онбординге, ротация — vault kv patch.
{{ with secret (printf "kv/data/projects/%s/%s/meta" (env "PROJECT_NAME") (env "ENV")) }}
BACKEND_TAG={{ .Data.data.backend_tag }}
{{ end }}
