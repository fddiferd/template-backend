FROM python:3.11-slim

WORKDIR /app

# Copy application files first
COPY app/ app/
COPY pyproject.toml .

# Install dependencies from pyproject.toml
RUN pip install .

# Set environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1
ENV ENVIRONMENT=production
ENV PYTHONPATH=/app

# Expose the application port
EXPOSE 8080

# Command to run the application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"] 