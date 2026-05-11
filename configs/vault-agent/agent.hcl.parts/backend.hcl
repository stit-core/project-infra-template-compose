# Profile: backend — KV-зависимости: kv/projects/<p>/<env>/{db,oidc,jwt}
# (OTEL_TOKEN приходит через always-on otel.env).
template {
  source      = "/etc/vault-agent/templates/backend.env.tpl"
  destination = "/secrets/backend.env"
  perms       = 0400
}
