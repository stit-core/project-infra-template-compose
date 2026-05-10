.PHONY: help deploy render validate ps logs restart hooks-install status backup

SHELL := /usr/bin/env bash

# Build compose file list dynamically.
COMPOSE_ARGS := -f docker-compose.yml $(addprefix -f ,$(wildcard compose/*.yml))

help:
	@awk 'BEGIN{FS=":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deploy: ## git pull + render-configs + compose up --wait (run on server)
	bash scripts/deploy.sh

render: ## render *.tpl configs through envsubst
	bash scripts/render-configs.sh

validate: ## syntax check compose + .env.example coverage
	bash scripts/agent-tools/validate.sh

ps: ## docker compose ps
	docker compose $(COMPOSE_ARGS) ps

logs: ## docker compose logs -f --tail=100
	docker compose $(COMPOSE_ARGS) logs -f --tail=100

restart: ## restart one service: make restart SVC=backend
	@if [ -z "$(SVC)" ]; then echo "usage: make restart SVC=<name>"; exit 2; fi
	docker compose $(COMPOSE_ARGS) restart $(SVC)

backup: ## one-shot restic backup (cron triggers this nightly)
	bash scripts/backup.sh

status: ## repo status summary (for /smartdev)
	bash scripts/agent-tools/status.sh

hooks-install: ## symlink scripts/git-hooks/* into .git/hooks/
	bash scripts/hooks-install.sh
