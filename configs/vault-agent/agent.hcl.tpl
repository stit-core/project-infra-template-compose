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

# Minio-credentials. Креды генерит scripts/new-env.sh (.onboard-creds),
# оператор относит блок корп-админу → vault kv put kv/projects/<p>/minio.
# Поля: root_user, root_password, app_access_key, app_secret_key,
# backup_access_key, backup_secret_key, buckets — space-separated, опц.
# Без seed'а vault-agent залипает в retry-loop'е и стек не поднимется.
template {
  source      = "/etc/vault-agent/templates/minio.env.tpl"
  destination = "/secrets/minio.env"
  perms       = 0400
}

# Backup-credentials. AWS-creds + RESTIC_PASSWORD оба в kv/projects/<p>/backup —
# чтобы endpoint и его creds жили в одном KV-path. RESTIC_REPOSITORY приходит
# из проектного .env (env-var, не KV). Для local-minio backup-SA creds совпадают
# с теми, что в kv/projects/<p>/minio (так new-env.sh их и подставляет по умолчанию);
# для external endpoint оператор подменяет access_key/secret_key руками перед `vault kv put`.
# RESTIC_PASSWORD ОБЯЗАТЕЛЬНО продублировать offsite — без него restore невозможен.
template {
  source      = "/etc/vault-agent/templates/backup.env.tpl"
  destination = "/secrets/backup.env"
  perms       = 0400
}

# Marker для healthcheck. Создаётся последним — чтобы зависимые
# сервисы (через `service_healthy`) стартовали только после того, как
# все секреты отрендерены.
template {
  contents    = "ready"
  destination = "/secrets/.ready"
  perms       = 0400
}
