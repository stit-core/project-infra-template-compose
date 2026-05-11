pid_file = "/tmp/vault-agent.pid"

vault {
  address = "${VAULT_ADDR}"
}

# AppRole login. role-id / secret-id пишутся trampoline-entrypoint'ом
# (compose/vault-agent.yml) в /secrets-bootstrap.
# remove_secret_id_file_after_reading=false — файл читается на каждом
# рестарте; для one-shot hardening переключить в true и re-seed на каждый deploy.
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

# Шаблоны рендерятся при auth и при каждом изменении source-данных
# (vault-agent держит blocking GET).

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

# Backup-credentials template. Раскомментируй ТОЛЬКО когда корп-сторона
# seed'нула kv/data/projects/<PROJECT_NAME>/backup (поля: repository, password,
# aws_access_key_id, aws_secret_access_key). Иначе vault-agent залипнет
# в retry-loop'е на отсутствующем secret'е и весь стек не поднимется.
# После включения — также подними backup-сервис: COMPOSE_PROFILES=backup.
# template {
#   source      = "/etc/vault-agent/templates/backup.env.tpl"
#   destination = "/secrets/backup.env"
#   perms       = 0400
# }

# Marker для healthcheck. Создаётся последним — чтобы зависимые
# сервисы (через `service_healthy`) стартовали только после того, как
# все секреты отрендерены.
template {
  contents    = "ready"
  destination = "/secrets/.ready"
  perms       = 0400
}
