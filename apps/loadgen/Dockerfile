# Same pattern as the backend image in observability-simulator:
# uv-based builder stage, slim runtime stage, non-root user.
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

WORKDIR /app

# Install dependencies from the lockfile first so this layer only rebuilds
# when dependencies change, not on every code edit
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY src/ src/
# --no-editable: by default uv installs the project as an editable install
# pointing at src/, which breaks when only .venv is copied to runtime
RUN uv sync --frozen --no-dev --no-editable

# --- Runtime stage ---
FROM python:3.12-slim-bookworm

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv

ENV PATH="/app/.venv/bin:$PATH"

# Non-root, same reasoning as the backend: runAsNonRoot-compatible
RUN useradd --system --uid 1001 --no-create-home appuser
USER 1001

CMD ["python", "-m", "loadgen"]
