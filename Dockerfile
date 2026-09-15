FROM python:3.13-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY pyproject.toml uv.lock .python-version ./
COPY apps ./apps
COPY api ./api

# Install Python dependencies
RUN pip install --no-cache-dir uv && uv sync --frozen --no-dev --no-editable
ENV PATH="/app/.venv/bin:$PATH"

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "apps.api.app.main:app", "--host", "0.0.0.0", "--port", "8000", "--limit-concurrency", "64", "--ws-max-size", "8192", "--no-access-log"]
