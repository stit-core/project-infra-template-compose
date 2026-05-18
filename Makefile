.PHONY: help validate doctor check ship deploy render ps logs restart backup restore-pg status search new-env setup plan-check

SHELL := /usr/bin/env bash

# Один словарь для агента: make <verb>. Concise-by-default; FORMAT=detailed —
# полный разбор (validate). Passthrough-аргументы: SVC= (restart/logs) /
# SNAPSHOT= (restore-pg) / Q=,P= (search) / ENV= (new-env) / A= (status) /
# MSG= (ship).
#
# compose интерполирует ${...} из --env-file. compose.env рендерится
# vault-agent'ом из kv/projects/<p>/<env>/meta (BACKEND_TAG etc.). Поздние
# --env-file перекрывают ранние; .env остаётся источником для identity и
# bootstrap-auth, compose.env — для Vault-managed конфига.
COMPOSE_ARGS := --env-file .env --env-file .runtime/env/compose.env \
                -f docker-compose.yml $(addprefix -f ,$(wildcard compose/*.yml))

help: ## сгруппированный список команд
	@awk 'BEGIN {FS = ":.*## "} \
		/^##@ / {printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next} \
		/^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

##@ LOOP
validate: ## Compose syntax + yamllint + .tpl + .env coverage (FORMAT=detailed)
	@bash scripts/tools/validate.sh $(if $(filter detailed,$(FORMAT)),--format=detailed)

doctor: ## Live fail-fast preflight: compose/vault-agent/dns/vault/env (A= --full)
	@bash scripts/tools/doctor.sh $(A)

check: ## Каноничный pre-ship gate: validate + doctor
	@echo "→ make validate"
	@$(MAKE) -s validate
	@echo "→ make doctor"
	@$(MAKE) -s doctor
	@echo "✓ check clean"

##@ SHIP
ship: ## commit + push + (если main) ssh-deploy. usage: make ship MSG="feat(foo): bar"
	bash scripts/ship.sh "$(MSG)"

deploy: ## на VPS: git pull + render + compose up --wait
	bash scripts/deploy.sh

render: ## envsubst для *.tpl + сборка agent.hcl из parts
	bash scripts/render-configs.sh

##@ OPS
ps: ## docker compose ps
	docker compose $(COMPOSE_ARGS) ps

logs: ## docker compose logs -f --tail=100 (SVC= один сервис)
	docker compose $(COMPOSE_ARGS) logs -f --tail=100 $(SVC)

restart: ## рестарт одного сервиса: make restart SVC=backend
	@if [ -z "$(SVC)" ]; then echo "usage: make restart SVC=<name>"; exit 2; fi
	docker compose $(COMPOSE_ARGS) restart $(SVC)

backup: ## one-shot backup внутри backup-контейнера (daily — busybox crond внутри)
	docker exec backup /usr/local/bin/backup-now

restore-pg: ## restore postgres из restic-снапшота. usage: make restore-pg SNAPSHOT=latest
	@if [ -z "$(SNAPSHOT)" ]; then echo "usage: make restore-pg SNAPSHOT=<id|latest>"; exit 2; fi
	bash scripts/restore-pg.sh "$(SNAPSHOT)"

##@ INTEL
status: ## Сводка состояния репо для smartdev (A= "--full")
	@bash scripts/tools/status.sh $(A)

search: ## Поиск по compose/configs/scripts/docs: make search Q=pattern [P=path]
	@if [ -z "$(Q)" ]; then echo "usage: make search Q=<pattern> [P=<path>]"; exit 2; fi
	@bash scripts/tools/search.sh "$(Q)" $(P)

##@ PROVISION
new-env: ## Bootstrap .env на чистом VPS (interactive; либо PROJECT_NAME=.. ENV=.. make new-env)
	@bash scripts/new-env.sh

##@ SETUP
setup: ## симлинк scripts/git-hooks/* → .git/hooks/
	bash scripts/hooks-install.sh

##@ META
plan-check: ## Валидатор структуры планов (.claude/plans/*.md) — тело A12
	@test -x scripts/tools/validate-plan.sh && bash scripts/tools/validate-plan.sh $(A) || echo "plan-check: not yet implemented (A12)"
