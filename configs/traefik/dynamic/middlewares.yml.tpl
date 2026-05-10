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

    secure-headers:
      headers:
        sslRedirect: true
        forceSTSHeader: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"

    rate-limit:
      rateLimit:
        average: 100
        burst: 200
