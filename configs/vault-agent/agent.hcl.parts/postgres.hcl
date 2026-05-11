# Profile: postgres — KV-зависимости: kv/projects/<p>/<env>/db
template {
  source      = "/etc/vault-agent/templates/postgres.env.tpl"
  destination = "/secrets/postgres.env"
  perms       = 0400
}
