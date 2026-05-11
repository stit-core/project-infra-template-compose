{{ with secret (printf "kv/data/projects/%s/%s/db" (env "PROJECT_NAME") (env "ENV")) }}
POSTGRES_USER={{ .Data.data.user }}
POSTGRES_PASSWORD={{ .Data.data.password }}
POSTGRES_DB={{ .Data.data.database }}
{{ end }}
