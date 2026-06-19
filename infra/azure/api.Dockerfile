FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

WORKDIR /app

RUN python -m pip install --upgrade pip \
    && python -m pip install uv

COPY pyproject.toml uv.lock .python-version ./
COPY apps ./apps
COPY api ./api

RUN uv pip install --system --no-cache .

EXPOSE 8000

CMD ["sh", "-c", "uvicorn apps.api.app.main:app --host 0.0.0.0 --port ${PORT:-8000} --no-access-log"]
