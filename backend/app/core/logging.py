"""Structured JSON logging with a request ID on every line.

Loki indexes labels, not log bodies, so the body has to carry what you will
search by. A request ID printed in the response header and repeated on every log
line for that request is what turns "this page was slow for me at 14:03" into a
query.

JSON rather than a formatted string because a log line is parsed far more often
than it is read.
"""

from __future__ import annotations

import json
import logging
import sys
from contextvars import ContextVar

# A ContextVar rather than a thread-local: this is an async application, and one
# thread serves many concurrent requests. A thread-local would attribute log
# lines to whichever request happened to be running.
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

_RESERVED = frozenset(logging.LogRecord("", 0, "", 0, "", None, None).__dict__)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": request_id_var.get(),
        }

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # Anything passed as extra= lands on the record alongside the standard
        # attributes. Copying only the non-standard keys keeps the line useful
        # without turning every log entry into a dump of the logging internals.
        for name, value in record.__dict__.items():
            if name not in _RESERVED and not name.startswith("_"):
                payload[name] = value

        return json.dumps(payload, default=str)


def configure(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)

    # Uvicorn installs its own handlers at import. Left alone, every request
    # would be logged twice: once as JSON and once in uvicorn's own format.
    for name in ("uvicorn", "uvicorn.error"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True

    # uvicorn.access is silenced entirely, and the application emits its own
    # access line instead.
    #
    # `--no-access-log` alone does not achieve this. It removes uvicorn's
    # handler but the records still propagate to root, so they reappeared
    # through the JSON handler -- and with request_id "-", because uvicorn logs
    # at the protocol layer, outside the ASGI middleware that sets the context.
    # The one line naming the path and status was the one line with no way to
    # correlate it.
    access = logging.getLogger("uvicorn.access")
    access.handlers = []
    access.propagate = False
