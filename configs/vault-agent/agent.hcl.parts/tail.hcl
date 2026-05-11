# Marker — рендерится статически (без Vault-deps), потому НЕ годится как
# healthcheck-сигнал sam-по-себе. Vault-agent healthcheck использует отдельный
# script-чек на все expected output-файлы (см. .runtime/configs/vault-health.sh,
# рендерится render-configs.sh учитывая активные profile'ы).
template {
  contents    = "ready"
  destination = "/secrets/.ready"
  perms       = 0400
}
