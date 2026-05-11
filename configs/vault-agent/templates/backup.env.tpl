{{ with secret (printf "kv/data/projects/%s/backup" (env "PROJECT_NAME")) }}
RESTIC_REPOSITORY={{ .Data.data.repository }}
RESTIC_PASSWORD={{ .Data.data.password }}
AWS_ACCESS_KEY_ID={{ .Data.data.aws_access_key_id }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.aws_secret_access_key }}
{{ end }}
