from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Response

from app.api.router import api_router
from app.core.config import settings
from app.core.datastores import datastores
from app.observability import metrics, tracing


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    # Neither handle contacts the network here, so an unreachable datastore
    # cannot prevent startup. The process comes up, reports itself live, and
    # reports itself not ready until the dependency answers.
    await datastores.start()
    try:
        yield
    finally:
        await datastores.stop()


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    docs_url="/docs" if settings.environment != "production" else None,
    redoc_url=None,
    lifespan=lifespan,
)
app.include_router(api_router)

# Middleware is registered before instrumentation so the metric records the
# duration the client actually experiences, including any tracing overhead.
app.middleware("http")(metrics.metrics_middleware)
metrics.initialise()
tracing.initialise(app)


@app.get(settings.metrics_path, include_in_schema=False)
async def metrics_endpoint() -> Response:
    """Prometheus exposition. Not routed publicly by any Ingress rule."""
    return metrics.render_metrics()
