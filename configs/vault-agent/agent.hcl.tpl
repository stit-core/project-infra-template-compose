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

# Minio-credentials template. Раскомментируй когда оператор сгенерировал
# minio-creds и положил в kv/data/projects/<PROJECT_NAME>/minio (поля:
# root_user, root_password, app_access_key, app_secret_key,
# backup_access_key, backup_secret_key, buckets — space-separated, опц).
# Эти же access/secret пары оператор передаёт stit-админу для реестра.
# Без секрета в Vault vault-agent залипнет в retry-loop'е — не раскомментируй
# до seed'а. После включения — COMPOSE_PROFILES=minio.
# template {
#   source      = "/etc/vault-agent/templates/minio.env.tpl"
#   destination = "/secrets/minio.env"
#   perms       = 0400
# }

# Backup-credentials template. Restic пишет в локальный minio (bucket
# "backups"), поэтому требует minio профиль. AWS-creds (backup-SA) берутся
# из того же kv/data/projects/<PROJECT_NAME>/minio пути; здесь только
# RESTIC_PASSWORD из отдельного /backup пути — оператор кладёт перед
# первым backup'ом (openssl rand -hex 32, ОБЯЗАТЕЛЬНО сохрани offsite —
# без него restore из снапшотов невозможен).
# Раскомментируй когда есть и minio-creds, и backup.password в Vault.
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
