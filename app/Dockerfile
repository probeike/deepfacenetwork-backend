# Use a lightweight Python base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy requirements file and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Expose port 80
EXPOSE 80

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Run the application
CMD ["python", "main.py"]