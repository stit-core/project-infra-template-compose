# RESTIC_REPOSITORY приходит из проектного .env (через vault-agent
# environment, см. compose/vault-agent.yml). Дефолт — внутренний minio
# через docker network: `s3:http://minio:9000/backups`.
RESTIC_REPOSITORY={{ env "RESTIC_REPOSITORY" }}
PROJECT_NAME={{ env "PROJECT_NAME" }}
{{ with secret (printf "kv/data/projects/%s/backup" (env "PROJECT_NAME")) }}
RESTIC_PASSWORD={{ .Data.data.password }}
{{ end }}
{{ with secret (printf "kv/data/projects/%s/minio" (env "PROJECT_NAME")) }}
AWS_ACCESS_KEY_ID={{ .Data.data.backup_access_key }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.backup_secret_key }}
{{ end }}
{{ with secret (printf "kv/data/projects/%s/db" (env "PROJECT_NAME")) }}
POSTGRES_USER={{ .Data.data.user }}
POSTGRES_PASSWORD={{ .Data.data.password }}
POSTGRES_HOST=postgres
{{ end }}
