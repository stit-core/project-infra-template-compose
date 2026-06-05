{{ with secret (printf "kv/data/projects/%s/%s/db" (env "PROJECT_NAME") (env "ENV")) }}
{{- /* MULTI-HOST: host/port опциональны в KV db — дефолт postgres:5432 (single-host,
       co-located). При split Postgres на отдельном хосте корп засевает db.host/db.port. */ -}}
PG_DSN=postgres://{{ .Data.data.user }}:{{ .Data.data.password }}@{{ or .Data.data.host "postgres" }}:{{ or .Data.data.port "5432" }}/{{ .Data.data.database }}?sslmode=disable
{{ end }}

{{ with secret (printf "kv/data/projects/%s/%s/oidc" (env "PROJECT_NAME") (env "ENV")) }}
OIDC_CLIENT_ID={{ .Data.data.client_id }}
OIDC_CLIENT_SECRET={{ .Data.data.client_secret }}
{{ end }}

{{ with secret (printf "kv/data/projects/%s/%s/jwt" (env "PROJECT_NAME") (env "ENV")) }}
JWT_SECRET={{ .Data.data.signing_key }}
{{ end }}
