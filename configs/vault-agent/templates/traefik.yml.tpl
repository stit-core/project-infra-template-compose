global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

ping:
  entryPoint: traefik

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
  traefik:
    address: ":8080"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: proxy
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      # email + caServer обязаны быть в файле (не CLI): traefik 3.6 при наличии
      # acme-блока в static yaml игнорирует --certificatesresolvers.*.acme.* флаги.
      # Значения приходят из kv/projects/<p>/<env>/meta — vault-agent рендерит
      # этот файл в .runtime/configs/traefik.yml, traefik читает через bind-mount.
{{ with secret (printf "kv/data/projects/%s/%s/meta" (env "PROJECT_NAME") (env "ENV")) }}
      email: {{ .Data.data.acme_email }}
      caServer: {{ .Data.data.acme_caserver }}
{{ end }}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

experimental:
  plugins:
    crowdsec-bouncer:
      moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      version: "v1.4.4"

log:
  level: INFO

accessLog:
  format: json
  filters:
    statusCodes: ["400-599"]
