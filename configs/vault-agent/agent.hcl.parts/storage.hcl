# Profile: storage (minio + backup) — KV-зависимости:
#   kv/projects/<p>/<env>/minio   (для minio-init + backup S3 creds)
#   kv/projects/<p>/<env>/backup  (для restic password + endpoint)
#   kv/projects/<p>/<env>/db      (для pg_dumpall в backup-контейнере)
# ВНИМАНИЕ: backup требует db-creds — storage профиль предполагает
# одновременную активацию postgres профиля. deploy.sh валидирует.
template {
  source      = "/etc/vault-agent/templates/minio.env.tpl"
  destination = "/secrets/minio.env"
  perms       = 0400
}

template {
  source      = "/etc/vault-agent/templates/backup.env.tpl"
  destination = "/secrets/backup.env"
  perms       = 0400
}
