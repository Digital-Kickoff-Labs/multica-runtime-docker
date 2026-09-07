COMPOSE ?= docker compose
SERVICE ?= multica-runtime

.PHONY: help build rebuild up down restart logs shell status login health prune

help:
	@grep -E '^[a-z-]+:.*?##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

build: ## Construit l'image
	$(COMPOSE) build

rebuild: ## Reconstruit en forcant un multica frais (contourne le cache du stage builder)
	$(COMPOSE) build --no-cache-filter multica-builder

up: ## Demarre le runtime
	$(COMPOSE) up -d

down: ## Arrete et supprime le conteneur (volumes conserves)
	$(COMPOSE) down

restart: ## Redemarre le service
	$(COMPOSE) restart $(SERVICE)

logs: ## Suit les logs
	$(COMPOSE) logs -f --tail=200 $(SERVICE)

shell: ## Ouvre un shell dans le conteneur
	$(COMPOSE) exec --user node $(SERVICE) bash

login: ## Login Multica interactif
	$(COMPOSE) exec --user node $(SERVICE) multica login --token

status: ## Etat du daemon
	$(COMPOSE) exec --user node $(SERVICE) multica daemon status

health: ## Etat de sante Docker
	docker inspect --format '{{ .State.Health.Status }}' $$($(COMPOSE) ps -q $(SERVICE))

prune: ## Supprime conteneur ET volumes nommes (auth perdue)
	$(COMPOSE) down -v
