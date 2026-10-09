http:
  middlewares:
    crowdsec:
      plugin:
        crowdsec-bouncer:
          enabled: true
          crowdsecMode: live
          crowdsecLapiKey: "${CROWDSEC_BOUNCER_API_KEY}"
          crowdsecLapiHost: "crowdsec:8080"
          crowdsecLapiScheme: http
          # Отказ WAF — 429, как у лимита частоты: краулер читает его как «приходи позже»,
          # а 403 — как «страницы нет». До сервиса запрос не доходит при любом коде.
          remediationStatusCode: 429

    # Состав общий для всех публичных роутеров. Content-Security-Policy ставит приложение;
    # X-Frame-Options и X-XSS-Protection не ставит никто.
    secure-headers:
      headers:
        forceSTSHeader: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        contentTypeNosniff: true
        referrerPolicy: "strict-origin-when-cross-origin"
        # Сервису, которому нужны камера, микрофон или геолокация, — свой middleware,
        # а не послабление здесь.
        permissionsPolicy: "camera=(), microphone=(), geolocation=()"

    # sourceCriterion у лимитов не задаётся: Traefik стоит на границе, источник — TCP-адрес
    # клиента. X-Forwarded-For здесь никем не подписан, лимит по нему обходится подделкой.
    rate-limit:
      rateLimit:
        average: 100
        burst: 200

    compress:
      compress:
        # zstd не включаем: выигрыша над br на HTML нет.
        encodings: [br, gzip]
        minResponseBodyBytes: 1024

    www-to-apex:
      redirectRegex:
        # Хост regexp не называет: его уже выбрал роутер, а Host с портом, заглавными
        # или точкой в конце правило Host() принимает — названный здесь хост на такой
        # записи не совпал бы. ${1} переживает envsubst: это не имя переменной.
        regex: "^https?://[^/]+/(.*)"
        replacement: "https://${DOMAIN}/${1}"
        permanent: true

    # Публичный POST формы: одна принятая заявка — одно письмо.
    form-rate-limit:
      rateLimit:
        average: 10
        period: 1m
        burst: 5

    form-body-limit:
      buffering:
        # Тело без Content-Length (chunked) приложение читает до 1 МиБ — 64 КиБ для него
        # держит только эта буферизация.
        maxRequestBodyBytes: 65536
        memRequestBodyBytes: 65536

    # Только для идемпотентных роутеров: повтор POST — вторая заявка.
    retry:
      retry:
        attempts: 2
        initialInterval: 100ms

    # Путь без внешнего доступа: 403 на edge, до процесса.
    deny-all:
      ipAllowList:
        sourceRange: ["127.0.0.1/32"]

    # Не-прод контур — парой и в этом порядке: staging-noindex перед staging-auth, иначе
    # ответ 401 уходит без X-Robots-Tag.
    staging-noindex:
      headers:
        customResponseHeaders:
          X-Robots-Tag: "noindex, nofollow, noarchive"

    staging-auth:
      basicAuth:
        # Файл рендерится из STAGING_BASIC_AUTH_USERS (.env) рядом с этим.
        usersFile: /etc/traefik/dynamic/staging.htpasswd
        realm: "staging"
