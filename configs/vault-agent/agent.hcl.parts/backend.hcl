# Profile: backend — KV-зависимости: kv/projects/<p>/<env>/{db,oidc,jwt}.
template {
  source      = "/etc/vault-agent/templates/backend.env.tpl"
  destination = "/secrets/backend.env"
  perms       = 0400
}
