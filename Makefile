# ZINO developer commands. `make help` lists them.
.DEFAULT_GOAL := help
SHELL := /bin/bash
AGENTS := services/zino-agents

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Create .env from the example and install dev dependencies
	@test -f .env || (cp .env.example .env && echo "created .env — fill in the secrets")
	cd $(AGENTS) && uv venv && uv pip install -e ".[dev]"

.PHONY: secrets
secrets: ## Print freshly generated values for the required secrets
	@echo "WEBUI_SECRET_KEY=$$(openssl rand -hex 32)"
	@echo "ZINO_API_KEY=$$(openssl rand -hex 32)"

.PHONY: test
test: ## Run the agent gateway test suite
	cd $(AGENTS) && .venv/bin/python -m pytest -q

.PHONY: lint
lint: ## Lint and format-check
	cd $(AGENTS) && .venv/bin/python -m ruff check . && .venv/bin/python -m ruff format --check .

.PHONY: fmt
fmt: ## Autoformat and autofix
	cd $(AGENTS) && .venv/bin/python -m ruff check --fix . && .venv/bin/python -m ruff format .

.PHONY: dev
dev: ## Run the agent gateway locally with reload, without Docker
	cd $(AGENTS) && .venv/bin/python -m uvicorn zino_agents.main:app --reload --port 8080

.PHONY: up
up: ## Start the full local stack
	docker compose up -d --build
	@echo "ZINO:    http://localhost:3000"
	@echo "gateway: http://localhost:8080/healthz"

.PHONY: down
down: ## Stop the local stack
	docker compose down

.PHONY: clean
clean: ## Stop the stack and delete its volumes (destroys local data)
	docker compose down -v

.PHONY: logs
logs: ## Tail logs from the local stack
	docker compose logs -f

.PHONY: tf-plan
tf-plan: ## Terraform plan
	cd infra/terraform && terraform init && terraform plan

.PHONY: tf-apply
tf-apply: ## Terraform apply
	cd infra/terraform && terraform apply
