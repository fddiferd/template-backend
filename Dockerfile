FROM python:3.11-slim

WORKDIR /app

# Copy project files
COPY pyproject.toml ./
COPY src/ ./src/

# Install dependencies using pip
RUN pip install --upgrade pip && \
    pip install .

# Set environment variables
ENV PORT=8000
ENV HOST=0.0.0.0

# Expose port
EXPOSE 8000

# Run the application
CMD uvicorn src.app:app --host ${HOST} --port ${PORT}