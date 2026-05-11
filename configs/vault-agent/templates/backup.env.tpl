# Restic пишет через публичный S3 endpoint (тот же URL, что и для внешних
# инструментов — mc / aws-cli со стороны stit-админа). Никакой привязки к
# docker-network: backup-контейнер ходит через traefik → minio, как любой
# внешний клиент. DOMAIN приходит из env vault-agent'а (см. compose/vault-agent.yml).
RESTIC_REPOSITORY=s3:https://s3.{{ env "DOMAIN" }}/backups
{{ with secret (printf "kv/data/projects/%s/backup" (env "PROJECT_NAME")) }}
RESTIC_PASSWORD={{ .Data.data.password }}
{{ end }}
{{ with secret (printf "kv/data/projects/%s/minio" (env "PROJECT_NAME")) }}
AWS_ACCESS_KEY_ID={{ .Data.data.backup_access_key }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.backup_secret_key }}
{{ end }}
