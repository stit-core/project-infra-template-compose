{{ with secret (printf "kv/data/projects/%s/db" (env "PROJECT_NAME")) }}
POSTGRES_USER={{ .Data.data.user }}
POSTGRES_PASSWORD={{ .Data.data.password }}
POSTGRES_DB={{ .Data.data.database }}
{{ end }}
