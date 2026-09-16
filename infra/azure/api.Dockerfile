FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

WORKDIR /app
ENV LALA_RUNTIME_PROFILE=api

RUN python -m pip install --upgrade pip \
    && python -m pip install uv

COPY pyproject.toml uv.lock .python-version ./
COPY apps ./apps
COPY api ./api

RUN uv sync --frozen --no-dev --no-editable
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

CMD ["sh", "-c", "exec uvicorn apps.api.app.main:app --host 0.0.0.0 --port ${PORT:-8000} --limit-concurrency 64 --ws-max-size 8192 --no-access-log"]
