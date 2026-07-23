.PHONY: help validate doctor check ship deploy render ps logs restart recreate build bump backup restore-pg ssh status search new-env setup plan-check project-check

SHELL := /usr/bin/env bash

# Один словарь для агента: make <verb>. Concise-by-default; FORMAT=detailed —
# полный разбор (validate). Passthrough-аргументы: SVC= (restart/logs) /
# SNAPSHOT= (restore-pg) / Q=,P= (search) / ENV= (new-env) / A= (status) /
# MSG= (ship).
#
# compose интерполирует ${...} из --env-file .env: identity, ACME, секреты
# профилей и image-теги (<SVC>_TAG — бампаются строго через .env, верб `bump`).
# .env — единственный источник секретов (см. .claude/rules/secrets-and-env.md).
COMPOSE_ARGS := --env-file .env \
                -f docker-compose.yml $(addprefix -f ,$(wildcard compose/*.yml))

help: ## сгруппированный список команд
	@awk 'BEGIN {FS = ":.*## "} \
		/^##@ / {printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next} \
		/^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

##@ LOOP
validate: ## Compose syntax + yamllint + .tpl + .env coverage (FORMAT=detailed)
	@bash scripts/tools/validate.sh $(if $(filter detailed,$(FORMAT)),--format=detailed)

doctor: ## Live fail-fast preflight: compose/render/dns/env (A= --full)
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

render: ## envsubst для configs/**/*.tpl из .env
	bash scripts/render-configs.sh

##@ OPS
# Ops-вербы выполняются НА VPS. Sentinel — наличие `.env` (живёт только на сервере):
# есть .env → локальный docker; нет → проксируем через scripts/tools/ssh.sh на VPS.
# Connection для ssh.sh — из .env.local (см. .claude/rules/{make-first,env-local}.md).
ps: ## статус сервисов (на VPS; с workstation — через ssh)
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) ps; \
	else bash scripts/tools/ssh.sh exec make ps; fi

logs: ## логи --tail=100, без follow (SVC= один сервис; с workstation — через ssh)
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) logs --tail=100 $(SVC); \
	else bash scripts/tools/ssh.sh exec make logs SVC=$(SVC); fi

restart: ## рестарт одного сервиса: make restart SVC=backend
	@if [ -z "$(SVC)" ]; then echo "usage: make restart SVC=<name>"; exit 2; fi
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) restart $(SVC); \
	else bash scripts/tools/ssh.sh exec make restart SVC=$(SVC); fi

recreate: ## пересоздать сервис — подхват ротированного .env-значения/тега (restart не перечитывает environment): make recreate SVC=backend
	@if [ -z "$(SVC)" ]; then echo "usage: make recreate SVC=<name>"; exit 2; fi
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) up -d --no-deps --force-recreate $(SVC); \
	else bash scripts/tools/ssh.sh exec make recreate SVC=$(SVC); fi

build: ## пересобрать образ сервиса с build-context (напр. backup после правки crontab): make build SVC=backup
	@if [ -z "$(SVC)" ]; then echo "usage: make build SVC=<name>"; exit 2; fi
	@if [ -f .env ]; then docker compose $(COMPOSE_ARGS) build $(SVC); \
	else bash scripts/tools/ssh.sh exec make build SVC=$(SVC); fi

# Единственный канон бампа image-тега: тег живёт в .env как <SVC>_TAG
# (UPPER_SNAKE). Верб правит .env на VPS и пересоздаёт сервис —
# compose сам подтянет отсутствующий образ (pull policy=missing).
bump: ## бамп image-тега через .env (<SVC>_TAG) + recreate: make bump SVC=backend TAG=v1.2.3
	@if [ -z "$(SVC)" ] || [ -z "$(TAG)" ]; then echo 'usage: make bump SVC=<name> TAG=<tag>'; exit 2; fi
	@if [ -f .env ]; then \
		var=$$(echo "$(SVC)" | tr '[:lower:]-' '[:upper:]_')_TAG; \
		if grep -q "^$$var=" .env; then sed -i "s|^$$var=.*|$$var=$(TAG)|" .env; \
		elif grep -q "^# $$var=" .env; then sed -i "s|^# $$var=.*|$$var=$(TAG)|" .env; \
		else printf '%s=%s\n' "$$var" "$(TAG)" >> .env; fi; \
		echo "→ $$var=$(TAG) (.env)"; \
		docker compose $(COMPOSE_ARGS) up -d --no-deps --force-recreate $(SVC); \
	else bash scripts/tools/ssh.sh exec make bump SVC=$(SVC) TAG=$(TAG); fi

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
# Оркестратор cockpit-сводки: локальный status.sh (git/roadmap/fragments, pure-local)
# + секция == Server == (серверный смок). Server по тому же .env-sentinel, что OPS:
# есть .env (на VPS) → smoke-run.sh локально; нет → ssh.sh smoke на VPS (недоступен
# → SKIP). status.sh docker/SSH не трогает — композит здесь. Финальный OK печатает таргет.
status: ## Сводка состояния репо + серверный смок для smartdev (A= "--full")
	@bash scripts/tools/status.sh $(A)
	@printf '\n== Server ==\n'
	@if [ -f .env ]; then bash scripts/tools/smoke-run.sh; \
	elif [ -f .env.local ]; then bash scripts/tools/ssh.sh smoke 2>/dev/null || echo "  SKIP (VPS недоступен — проверь .env.local / сеть)"; \
	else echo "  SKIP (нет .env.local — connection не задан, серверный смок пропущен)"; fi
	@echo; echo "OK"

search: ## Поиск по compose/configs/scripts/docs: make search Q=pattern [P=path]
	@if [ -z "$(Q)" ]; then echo "usage: make search Q=<pattern> [P=<path>]"; exit 2; fi
	@bash scripts/tools/search.sh "$(Q)" $(P)

##@ PROVISION
new-env: ## Bootstrap .env на чистом VPS (interactive; либо PROJECT_NAME=.. ENV=.. make new-env)
	@bash scripts/new-env.sh

##@ SETUP
setup: ## git-хуки (commit-msg, pre-commit) + dev-deps (PyYAML для frontmatter-проверки)
	bash scripts/setup.sh

##@ META
plan-check: ## Валидатор структуры единого плана .claude/plans/roadmap.md (A=<file> override)
	@bash scripts/tools/validate-plan.sh $(A)

project-check: ## Валидатор инфра-слоя docs/project/ (stack + service-doc'и; A=<path> override)
	@bash scripts/tools/validate-project-doc.sh $(A)
