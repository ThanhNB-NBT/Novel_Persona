FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY novelworker ./novelworker

# Mặc định chạy crawler; docker-compose override 'command' cho service translator.
CMD ["python", "-m", "novelworker.main", "crawl"]
