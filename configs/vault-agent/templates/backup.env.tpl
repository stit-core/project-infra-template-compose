# RESTIC_REPOSITORY + creds живут в одном KV-path (kv/projects/<p>/<env>/backup) —
# так endpoint и его credentials ротируются вместе. Для local-minio rehearsal
# repository указывает на http://minio:9000/<bucket> и creds совпадают с
# backup-SA из minio-объекта; для external endpoint админ выставляет реальные.
# RESTIC_PASSWORD ОБЯЗАТЕЛЬНО продублирован offsite — без него restore невозможен.
PROJECT_NAME={{ env "PROJECT_NAME" }}
{{ with secret (printf "kv/data/projects/%s/%s/backup" (env "PROJECT_NAME") (env "ENV")) }}
RESTIC_REPOSITORY={{ .Data.data.repository }}
RESTIC_PASSWORD={{ .Data.data.password }}
AWS_ACCESS_KEY_ID={{ .Data.data.access_key }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.secret_key }}
{{ end }}
{{ with secret (printf "kv/data/projects/%s/%s/db" (env "PROJECT_NAME") (env "ENV")) }}
POSTGRES_USER={{ .Data.data.user }}
POSTGRES_PASSWORD={{ .Data.data.password }}
POSTGRES_HOST=postgres
{{ end }}
