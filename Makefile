.PHONY: help validate doctor check ship deploy render ps logs restart backup restore-pg ssh status search new-env setup plan-check project-check

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

check: ## Каноничный pre-ship gate: validate + doctor + plan-check + project-check
	@echo "→ make validate"
	@$(MAKE) -s validate
	@echo "→ make doctor"
	@$(MAKE) -s doctor
	@echo "→ make plan-check"
	@$(MAKE) -s plan-check
	@echo "→ make project-check"
	@$(MAKE) -s project-check
	@echo "✓ check clean"

##@ SHIP
ship: ## commit + push + (если main) ssh-deploy. usage: make ship MSG="feat(foo): bar"
	bash scripts/ship.sh "$(MSG)"

deploy: ## на VPS: git pull + render + compose up --wait
	bash scripts/deploy.sh

render: ## envsubst для *.tpl + сборка agent.hcl из parts
	bash scripts/render-configs.sh

##@ OPS
# Ops-вербы выполняются НА VPS. Sentinel — наличие `.env` (живёт только на сервере):
# есть .env → локальный docker; нет → проксируем через scripts/tools/ssh.sh на VPS.
# Connection для ssh.sh — из .env.local (см. .claude/rules/{make-first,env-local}.md).
ps: ## статус сервисов (на VPS; с workstation — через ssh)
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) ps; \
	else bash scripts/tools/ssh.sh exec make ps; fi

logs: ## логи -f --tail=100 (SVC= один сервис; с workstation — через ssh)
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) logs -f --tail=100 $(SVC); \
	else bash scripts/tools/ssh.sh exec make logs SVC=$(SVC); fi

restart: ## рестарт одного сервиса: make restart SVC=backend
	@if [ -z "$(SVC)" ]; then echo "usage: make restart SVC=<name>"; exit 2; fi
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) restart $(SVC); \
	else bash scripts/tools/ssh.sh exec make restart SVC=$(SVC); fi

backup: ## one-shot backup (на VPS; с workstation — через ssh)
	@if [ -f .env ]; then docker exec backup /usr/local/bin/backup-now; \
	else bash scripts/tools/ssh.sh exec make backup; fi

restore-pg: ## restore postgres из restic: make restore-pg SNAPSHOT=latest
	@if [ -z "$(SNAPSHOT)" ]; then echo "usage: make restore-pg SNAPSHOT=<id|latest>"; exit 2; fi
	@if [ -f .env ]; then bash scripts/restore-pg.sh "$(SNAPSHOT)"; \
	else bash scripts/tools/ssh.sh exec make restore-pg SNAPSHOT=$(SNAPSHOT); fi

ssh: ## выполнить команду на VPS: make ssh CMD="docker ps"
	@if [ -z "$(CMD)" ]; then echo 'usage: make ssh CMD="<command>"'; exit 2; fi
	@bash scripts/tools/ssh.sh exec $(CMD)

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
plan-check: ## Валидатор структуры единого плана .claude/plans/roadmap.md (A=<file> override)
	@bash scripts/tools/validate-plan.sh $(A)

project-check: ## Валидатор продуктового слоя docs/project/ (A=<path> override)
	@bash scripts/tools/validate-project-doc.sh $(A)
