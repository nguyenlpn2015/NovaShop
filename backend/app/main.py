from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.router import api_router
from app.core.config import settings
from app.core.datastores import datastores


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
