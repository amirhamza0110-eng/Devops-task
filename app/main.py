"""Small FastAPI service: JSON logs, Prometheus metrics, env-driven config."""
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone

import uvicorn
from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

PORT = int(os.getenv("PORT", "8080"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")
VERSION = os.getenv("APP_VERSION", "1.0.0")


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        data = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname.lower(),
            "msg": record.getMessage(),
            "env": ENVIRONMENT,
        }
        data.update(getattr(record, "fields", {}))
        return json.dumps(data)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("app")
log.handlers = [handler]
log.setLevel(LOG_LEVEL)
log.propagate = False

REQUESTS = Counter("http_requests", "Total HTTP requests", ["method", "path", "status"])
ERRORS = Counter("http_errors", "Total HTTP 5xx responses", ["method", "path"])
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency in seconds",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)

app = FastAPI(title="devops-task")


@app.middleware("http")
async def observe(request: Request, call_next):
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        elapsed = time.perf_counter() - start
        route = request.scope.get("route")
        # Route template (not raw URL) keeps label cardinality bounded.
        path = route.path if route else "unmatched"
        REQUESTS.labels(request.method, path, str(status)).inc()
        LATENCY.labels(request.method, path).observe(elapsed)
        if status >= 500:
            ERRORS.labels(request.method, path).inc()
        if path != "/metrics":
            lvl = logging.ERROR if status >= 500 else (
                logging.DEBUG if path == "/health" else logging.INFO)
            log.log(lvl, "request", extra={"fields": {
                "method": request.method, "path": path, "status": status,
                "duration_ms": round(elapsed * 1000, 2)}})


@app.get("/")
def root():
    return {"message": "Hello from DevOps Task!", "status": "running", "version": VERSION}


@app.get("/health")
def health():
    raise HTTPException(status_code=500, detail="intentional rollback test")


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/boom")
def boom():
    """Demo endpoint to generate 5xx errors for dashboards/alerts."""
    raise HTTPException(status_code=500, detail="intentional error")


if __name__ == "__main__":
    # uvicorn installs SIGTERM/SIGINT handlers: it stops accepting connections,
    # finishes in-flight requests, then exits (graceful shutdown).
    log.info("starting", extra={"fields": {"port": PORT, "version": VERSION}})
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_config=None, access_log=False)  # nosec B104
