# syntax=docker/dockerfile:1
FROM python:3.12.7-alpine3.20 AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12.7-alpine3.20
ARG VERSION=1.0.0
ARG REVISION=unknown
LABEL org.opencontainers.image.title="devops-task" \
      org.opencontainers.image.description="Hello DevOps task service" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.source="https://github.com/amirhamza0110-eng/Devops-task"
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    PORT=8080 LOG_LEVEL=INFO ENVIRONMENT=production APP_VERSION=${VERSION}
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
COPY --from=builder /install /usr/local
WORKDIR /app
COPY app ./app
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["python", "-m", "app.healthcheck"]
CMD ["python", "-m", "app.main"]
