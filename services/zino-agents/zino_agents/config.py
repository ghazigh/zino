"""Runtime configuration, sourced from the environment.

Every setting is prefixed ``ZINO_`` so it cannot collide with the Open WebUI
variables that share the same Cloud Run project.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ZINO_", env_file=".env", extra="ignore")

    # Service identity
    env: str = "dev"
    log_level: str = "INFO"

    # Cloud Run injects PORT; uvicorn is started with it in the Dockerfile CMD.
    port: int = 8080

    # Shared secret that Open WebUI presents as its OpenAI API key. When unset
    # the gateway runs unauthenticated, which is only acceptable on localhost —
    # `require_auth` enforces that.
    api_key: str | None = None

    # Upstream model provider the agents delegate raw completions to.
    upstream_base_url: str = "https://api.openai.com/v1"
    upstream_api_key: str | None = None
    upstream_model: str = "gpt-4o-mini"

    # Agent execution limits.
    max_tool_iterations: int = 8
    request_timeout_s: float = 120.0

    @property
    def is_production(self) -> bool:
        return self.env.lower() in {"prod", "production"}

    @property
    def require_auth(self) -> bool:
        """Auth is mandatory anywhere that is not a local dev run."""
        return self.is_production or self.api_key is not None


settings = Settings()
