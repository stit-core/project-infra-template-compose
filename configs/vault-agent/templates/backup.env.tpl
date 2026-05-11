# Restic пишет в локальный minio (bucket "backups", создаётся minio-init'ом).
# RESTIC_REPOSITORY зашит — bucket всегда называется backups, endpoint всегда
# внутренний minio:9000. AWS-creds — backup-SA, который оператор сгенерировал
# и положил в kv/data/projects/<p>/minio при подъёме minio. RESTIC_PASSWORD —
# отдельный Vault-path /backup (восстановление через DR-skill требует его без
# доступа к minio-SA, поэтому изолирован).
RESTIC_REPOSITORY=s3:http://minio:9000/backups
{{ with secret (printf "kv/data/projects/%s/backup" (env "PROJECT_NAME")) }}
RESTIC_PASSWORD={{ .Data.data.password }}
{{ end }}
{{ with secret (printf "kv/data/projects/%s/minio" (env "PROJECT_NAME")) }}
AWS_ACCESS_KEY_ID={{ .Data.data.backup_access_key }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.backup_secret_key }}
{{ end }}
