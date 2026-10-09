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
    # Контейнер без здоровья — неудачная выкатка, unhealthy — оставляет свои роутеры с
    # пустым сервисом: его адреса отвечают 5xx (503; первые секунды, до пробы сервиса, —
    # 500), а не роутером ниже приоритетом — заглушка отдала бы на корне свою страницу с
    # кодом 200.
    allowEmptyServices: true
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      # email + caServer обязаны быть в файле (не CLI): traefik 3.6 при наличии
      # acme-блока в static yaml игнорирует --certificatesresolvers.*.acme.* флаги.
      # Значения приходят из .env (ACME_EMAIL / ACME_CASERVER) — render-configs.sh
      # рендерит этот файл envsubst'ом в configs/traefik/traefik.yml (gitignored),
      # traefik читает его через bind-mount.
      email: ${ACME_EMAIL}
      caServer: ${ACME_CASERVER}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

experimental:
  plugins:
    crowdsec-bouncer:
      moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      version: "v1.4.4"

log:
  # Не тише INFO: по строке «Plugins loaded» make deploy сверяет загрузку плагина bouncer.
  level: INFO

# Журнал доступа — файл в каталоге хоста (compose/traefik.yml): его читают CrowdSec
# (configs/crowdsec/acquis.yaml) и отчёт «бот × статус». Пишется каждый ответ: сценарии
# обхода CrowdSec считают и 2xx. User-Agent — иначе ботов в журнале не видно;
# X-Request-Id сшивает запись со строкой лога сервиса. Ротация — расписание стека
# (configs/crowdsec/crontab).
accessLog:
  filePath: /var/log/traefik/access.log
  format: json
  fields:
    headers:
      names:
        User-Agent: keep
        X-Request-Id: keep
