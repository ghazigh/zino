# ZINO developer commands. `make help` lists them.
.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Create .env from the example
	@test -f .env || (cp .env.example .env && echo "created .env — now run 'make secrets'")

.PHONY: secrets
secrets: ## Print a freshly generated WEBUI_SECRET_KEY
	@echo "WEBUI_SECRET_KEY=$$(openssl rand -hex 32)"

.PHONY: up
up: ## Start the local stack
	docker compose up -d
	@echo "ZINO: http://localhost:3000"

.PHONY: down
down: ## Stop the local stack
	docker compose down

.PHONY: clean
clean: ## Stop the stack and delete its volumes (destroys local data)
	docker compose down -v

.PHONY: logs
logs: ## Tail logs from the local stack
	docker compose logs -f

.PHONY: pull
pull: ## Pull the pinned upstream image
	docker compose pull

.PHONY: check
check: ## Validate compose and Terraform
	docker compose config --quiet && echo "compose OK"
	cd infra/terraform && terraform fmt -check -recursive && echo "terraform fmt OK"

.PHONY: tf-plan
tf-plan: ## Terraform plan
	cd infra/terraform && terraform init && terraform plan

.PHONY: tf-apply
tf-apply: ## Terraform apply
	cd infra/terraform && terraform apply
