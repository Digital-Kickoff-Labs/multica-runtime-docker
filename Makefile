COMPOSE ?= docker compose
SERVICE ?= multica-runtime

.PHONY: help build rebuild up down restart logs shell status login health prune

help:
	@grep -E '^[a-z-]+:.*?##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

build: ## Build the image
	$(COMPOSE) build

rebuild: ## Rebuild with a fresh multica (bypasses the builder stage cache)
	$(COMPOSE) build --no-cache-filter multica-builder

up: ## Start the runtime
	$(COMPOSE) up -d

down: ## Stop and remove the container (volumes are kept)
	$(COMPOSE) down

restart: ## Restart the service
	$(COMPOSE) restart $(SERVICE)

logs: ## Follow the logs
	$(COMPOSE) logs -f --tail=200 $(SERVICE)

shell: ## Open a shell in the container
	$(COMPOSE) exec --user node $(SERVICE) bash

login: ## Interactive Multica login
	$(COMPOSE) exec --user node $(SERVICE) multica login --token

status: ## Daemon status
	$(COMPOSE) exec --user node $(SERVICE) multica daemon status

health: ## Docker health status
	docker inspect --format '{{ .State.Health.Status }}' $$($(COMPOSE) ps -q $(SERVICE))

prune: ## Remove container AND named volumes (auth is lost)
	$(COMPOSE) down -v
