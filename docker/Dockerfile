FROM python:3.11-slim

WORKDIR /app

# Copy project files
COPY pyproject.toml ./
COPY config ./
COPY app/ ./app/
COPY README.md ./

# Copy Firebase service account credentials
COPY service_accounts/ ./service_accounts/

# Install dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -e .

# Expose port
EXPOSE 8080

# Set environment variables
ENV HOST=0.0.0.0
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Start the application
CMD ["uvicorn", "app.run:app", "--host", "0.0.0.0", "--port", "8080"]