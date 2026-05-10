pid_file = "/tmp/vault-agent.pid"

vault {
  address = "${VAULT_ADDR}"
}

# AppRole login. Role-id and secret-id come from environment, written
# to a file at startup by the trampoline entrypoint (compose/vault-agent.yml).
# remove_secret_id_file_after_reading=false keeps the file usable across
# restarts; for one-shot hardening flip to true and re-seed on deploy.
auto_auth {
  method "approle" {
    config = {
      role_id_file_path                   = "/secrets-bootstrap/role-id"
      secret_id_file_path                 = "/secrets-bootstrap/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/secrets/.vault-token"
      mode = 0400
    }
  }
}

# Templates render once on auth and re-render whenever the source data
# in Vault changes (vault-agent watches via blocking GET).

template {
  source      = "/etc/vault-agent/templates/backend.env.tpl"
  destination = "/secrets/backend.env"
  perms       = 0400
}

template {
  source      = "/etc/vault-agent/templates/postgres.env.tpl"
  destination = "/secrets/postgres.env"
  perms       = 0400
}

# Marker file used by vault-agent's healthcheck. Created last so other
# containers waiting on `service_healthy` only proceed once secrets are
# fully materialized.
template {
  contents    = "ready"
  destination = "/secrets/.ready"
  perms       = 0400
}
