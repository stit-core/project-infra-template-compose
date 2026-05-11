{{ with secret (printf "kv/data/projects/%s/minio" (env "PROJECT_NAME")) }}
MINIO_ROOT_USER={{ .Data.data.root_user }}
MINIO_ROOT_PASSWORD={{ .Data.data.root_password }}
APP_S3_ACCESS_KEY={{ .Data.data.app_access_key }}
APP_S3_SECRET_KEY={{ .Data.data.app_secret_key }}
BACKUP_S3_ACCESS_KEY={{ .Data.data.backup_access_key }}
BACKUP_S3_SECRET_KEY={{ .Data.data.backup_secret_key }}
MINIO_BUCKETS={{ or (index .Data.data "buckets") "" }}
{{ end }}
