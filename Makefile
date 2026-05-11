.PHONY: help deploy render validate ps logs restart hooks-install status backup ship

SHELL := /usr/bin/env bash

# compose интерполирует ${...} из --env-file. compose.env рендерится
# vault-agent'ом из kv/projects/<p>/<env>/meta (BACKEND_TAG etc.). Поздние
# --env-file перекрывают ранние; .env остаётся источником для identity и
# bootstrap-auth, compose.env — для Vault-managed конфига.
COMPOSE_ARGS := --env-file .env --env-file .runtime/env/compose.env \
                -f docker-compose.yml $(addprefix -f ,$(wildcard compose/*.yml))

help:
	@awk 'BEGIN{FS=":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deploy: ## на VPS: git pull + render + compose up --wait
	bash scripts/deploy.sh

ship: ## commit + push + (если main) ssh-deploy. usage: make ship MSG="feat(foo): bar"
	bash scripts/ship.sh "$(MSG)"

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

backup: ## one-shot backup внутри backup-контейнера (daily — busybox crond внутри)
	docker exec backup /usr/local/bin/backup-now

restore-pg: ## restore postgres из restic-снапшота. usage: make restore-pg SNAPSHOT=latest
	@if [ -z "$(SNAPSHOT)" ]; then echo "usage: make restore-pg SNAPSHOT=<id|latest>"; exit 2; fi
	bash scripts/restore-pg.sh "$(SNAPSHOT)"

status: ## сводка состояния репо (для /smartdev)
	bash scripts/agent-tools/status.sh

hooks-install: ## симлинк scripts/git-hooks/* → .git/hooks/
	bash scripts/hooks-install.sh
