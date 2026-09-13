# syntax=docker/dockerfile:1

FROM python:3.11-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dependencies first so application edits do not invalidate the layer.
COPY pyproject.toml ./
RUN pip install --no-cache-dir \
      "fastapi>=0.115" "uvicorn[standard]>=0.32" "pydantic>=2.9" \
      "pydantic-settings>=2.6" "httpx>=0.27"

COPY zino_agents ./zino_agents

# Cloud Run requires a non-root user and delivers the listen port in $PORT.
RUN useradd --create-home --uid 1000 zino && chown -R zino:zino /app
USER zino

ENV PORT=8080
EXPOSE 8080

# Shell form so $PORT is expanded at runtime rather than baked in.
CMD exec uvicorn zino_agents.main:app --host 0.0.0.0 --port ${PORT} --workers 1
