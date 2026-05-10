.PHONY: help deploy render validate ps logs restart hooks-install status backup

SHELL := /usr/bin/env bash

COMPOSE_ARGS := -f docker-compose.yml $(addprefix -f ,$(wildcard compose/*.yml))

help:
	@awk 'BEGIN{FS=":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deploy: ## git pull + render-configs + compose up --wait (запускать на сервере)
	bash scripts/deploy.sh

render: ## envsubst для *.tpl
	bash scripts/render-configs.sh

validate: ## compose syntax + .env.example coverage
	bash scripts/agent-tools/validate.sh

ps: ## docker compose ps
	docker compose $(COMPOSE_ARGS) ps

logs: ## docker compose logs -f --tail=100
	docker compose $(COMPOSE_ARGS) logs -f --tail=100

restart: ## рестарт одного сервиса: make restart SVC=backend
	@if [ -z "$(SVC)" ]; then echo "usage: make restart SVC=<name>"; exit 2; fi
	docker compose $(COMPOSE_ARGS) restart $(SVC)

backup: ## one-shot restic backup (триггерится host-cron'ом ночью)
	bash scripts/backup.sh

status: ## сводка состояния репо (для /smartdev)
	bash scripts/agent-tools/status.sh

hooks-install: ## симлинк scripts/git-hooks/* → .git/hooks/
	bash scripts/hooks-install.sh
