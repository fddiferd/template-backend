FROM python:3.11-slim

WORKDIR /app

# Copy project definition
COPY pyproject.toml ./

# Copy application code
COPY app/ ./app/
COPY README.md ./

# Install dependencies directly from pyproject.toml
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -e .

# Set environment variables
ENV PORT=8000
ENV HOST=0.0.0.0
ENV PYTHONUNBUFFERED=1

# Expose port
EXPOSE 8000

# Run the application with uvicorn
CMD ["uvicorn", "app.run:app", "--host", "0.0.0.0", "--port", "8080"]