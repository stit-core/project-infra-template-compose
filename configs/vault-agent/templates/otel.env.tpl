{{ with secret (printf "kv/data/projects/%s/%s/otel" (env "PROJECT_NAME") (env "ENV")) }}
OTEL_TOKEN={{ .Data.data.token }}
{{ end }}
OTEL_TENANT={{ env "PROJECT_NAME" }}-{{ env "ENV" }}
