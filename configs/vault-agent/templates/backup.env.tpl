# RESTIC_REPOSITORY приходит из проектного .env (через vault-agent
# environment, см. compose/vault-agent.yml). Local-default убран —
# оператор задаёт endpoint в .env (см. .env.example).
#
# AWS-creds — из kv/projects/<p>/backup (НЕ из minio path). Так restic
# может ходить хоть на проектный minio, хоть на external S3 — endpoint
# и его creds живут вместе, в одном KV-path. Для local-minio операторы
# кладут backup-SA creds (см. show-onboard-creds.sh output); для external
# — реальные креды endpoint'а.
RESTIC_REPOSITORY={{ env "RESTIC_REPOSITORY" }}
PROJECT_NAME={{ env "PROJECT_NAME" }}
{{ with secret (printf "kv/data/projects/%s/backup" (env "PROJECT_NAME")) }}
RESTIC_PASSWORD={{ .Data.data.password }}
AWS_ACCESS_KEY_ID={{ .Data.data.access_key }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.secret_key }}
{{ end }}
{{ with secret (printf "kv/data/projects/%s/db" (env "PROJECT_NAME")) }}
POSTGRES_USER={{ .Data.data.user }}
POSTGRES_PASSWORD={{ .Data.data.password }}
POSTGRES_HOST=postgres
{{ end }}
