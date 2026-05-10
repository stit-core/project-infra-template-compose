{{ with secret (printf "kv/data/projects/%s/db" (env "PROJECT_NAME")) }}
PG_DSN=postgres://{{ .Data.data.user }}:{{ .Data.data.password }}@postgres:5432/{{ .Data.data.database }}?sslmode=disable
{{ end }}

{{ with secret (printf "kv/data/projects/%s/oidc" (env "PROJECT_NAME")) }}
OIDC_CLIENT_ID={{ .Data.data.client_id }}
OIDC_CLIENT_SECRET={{ .Data.data.client_secret }}
{{ end }}

{{ with secret (printf "kv/data/projects/%s/jwt" (env "PROJECT_NAME")) }}
JWT_SIGNING_KEY={{ .Data.data.signing_key }}
{{ end }}

{{ with secret (printf "kv/data/observability/tenants/%s" (env "PROJECT_NAME")) }}
OTEL_TOKEN={{ .Data.data.token }}
{{ end }}
