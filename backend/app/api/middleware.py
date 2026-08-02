"""Request identity.

Every request gets an ID. It goes into the logging context so each line for that
request carries it, and into the response header so a reader can quote it. That
pairing is what makes a report like "it was slow at 14:03" answerable: the ID
from the header goes straight into a Loki query.

An inbound X-Request-ID is honoured when it looks like one, so a trace survives
the frontend's server-side fetch into the backend rather than becoming two
unrelated ids.
"""

from __future__ import annotations

import logging
import time
import uuid
from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.logging import request_id_var
from app.observability.metrics import route_template

logger = logging.getLogger("novashop.access")

HEADER = "X-Request-ID"
MAX_LENGTH = 64


def _acceptable(value: str | None) -> bool:
    """Reject anything that would be unpleasant in a log line or a header.

    A caller-supplied value is untrusted input. Without this, a newline in the
    header forges log entries, and an unbounded string bloats every line for
    that request.
    """
    if not value or len(value) > MAX_LENGTH:
        return False
    return all(c.isalnum() or c in "-_" for c in value)


async def request_id_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    inbound = request.headers.get(HEADER)
    request_id = inbound if _acceptable(inbound) else uuid.uuid4().hex[:16]

    token = request_id_var.set(request_id)
    started = time.perf_counter()
    try:
        response = await call_next(request)

        # The application's own access line, replacing uvicorn's. It is emitted
        # here, before the context is reset, and that ordering is the whole
        # point: an earlier version logged after the `finally`, so every line
        # carried request_id "-" while the header carried the real value. The
        # header and the log disagreeing is worse than neither having an ID,
        # because the ID looks usable and matches nothing.
        #
        # Labelled with the matched route template rather than the raw path --
        # the same bounding rule the metrics use, applied to logs so the two
        # can be joined on `route`.
        if request.url.path != settings.metrics_path:
            logger.info(
                "request completed",
                extra={
                    "method": request.method,
                    "route": route_template(request),
                    "path": request.url.path,
                    "status": response.status_code,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 2),
                },
            )
    finally:
        request_id_var.reset(token)

    response.headers[HEADER] = request_id
    return response


# Paths a fault must never affect.
#
# Liveness must keep answering: a 503 there restarts the container, which ends
# the demonstration and, in a real incident, removes the process that could have
# explained itself. /metrics must keep answering because the whole purpose of
# the fault is to move a metric, and a scrape failure would replace the signal
# with an absence.
FAULT_EXEMPT = frozenset({"/live", "/health", "/metrics", "/demo/fault"})


async def fault_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Return 503 for application traffic while a fault is active.

    Deliberately not an exception: raising would produce a stack trace in the
    logs on every request and bury the reason. A plain 503 with a body that says
    it is deliberate is what an operator needs to see.
    """
    from app.api.routes.shop import fault_is_active

    if fault_is_active() and request.url.path not in FAULT_EXEMPT:
        logger.warning(
            "request failed by fault injection",
            extra={"method": request.method, "path": request.url.path, "status": 503},
        )
        return JSONResponse(
            status_code=503,
            content={
                "detail": "Fault injection is active. This failure is deliberate.",
            },
        )

    return await call_next(request)
