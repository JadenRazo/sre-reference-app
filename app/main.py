"""Flask reference app for the SRE demo.

Two endpoints:
- GET /health   always 200, used by ALB health checks and Docker HEALTHCHECK
- GET /         200 most of the time, ~5% intentional 500s so the SLO burn-rate
                alarms have something to measure against
"""
import json
import logging
import os
import random
import sys
import time
import uuid
from datetime import datetime, timezone
from flask import Flask, g, jsonify, request

ERROR_RATE = float(os.environ.get("ERROR_RATE", "0.05"))
APP_NAME = os.environ.get("APP_NAME", "sre-reference-app")
APP_VERSION = os.environ.get("APP_VERSION", "dev")


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "app": APP_NAME,
            "version": APP_VERSION,
        }
        for key in ("request_id", "method", "path", "status", "duration_ms", "remote_addr"):
            value = getattr(record, key, None)
            if value is not None:
                payload[key] = value
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(payload)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
root = logging.getLogger()
root.handlers = [handler]
root.setLevel(logging.INFO)
logging.getLogger("werkzeug").setLevel(logging.WARNING)

log = logging.getLogger(APP_NAME)
app = Flask(APP_NAME)


@app.before_request
def _before():
    g.start = time.perf_counter()
    g.request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())


@app.after_request
def _after(response):
    duration_ms = round((time.perf_counter() - g.start) * 1000, 2)
    response.headers["X-Request-ID"] = g.request_id
    log.info(
        "request",
        extra={
            "request_id": g.request_id,
            "method": request.method,
            "path": request.path,
            "status": response.status_code,
            "duration_ms": duration_ms,
            "remote_addr": request.headers.get("X-Forwarded-For", request.remote_addr),
        },
    )
    return response


@app.route("/health")
def health():
    return jsonify(status="ok", app=APP_NAME, version=APP_VERSION), 200


@app.route("/")
def root_endpoint():
    if random.random() < ERROR_RATE:
        return jsonify(error="intermittent", request_id=g.request_id), 500
    return jsonify(hello="world", request_id=g.request_id), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
