FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml uv.lock .python-version ./
COPY apps ./apps
COPY api ./api

RUN pip install --no-cache-dir uv && uv sync --frozen --no-dev --no-editable
ENV PATH="/app/.venv/bin:$PATH"

COPY . .

EXPOSE 8000

CMD ["uvicorn", "apps.api.app.main:app", "--host", "0.0.0.0", "--port", "8000", "--limit-concurrency", "64", "--ws-max-size", "8192", "--no-access-log"]
