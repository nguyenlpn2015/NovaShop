from fastapi import APIRouter, Response, status

from app.core.config import settings
from app.core.datastores import datastores
from app.schemas.health import (
    DependencyHealth,
    HealthResponse,
    LivenessResponse,
    ReadinessResponse,
)

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    """Service identity. Retained for existing callers and dashboards.

    This endpoint reports no dependency state. Use /ready to decide whether the
    replica can serve traffic.
    """
    return HealthResponse(
        status="healthy",
        service=settings.app_name,
        version=settings.app_version,
    )


@router.get("/live", response_model=LivenessResponse)
async def live() -> LivenessResponse:
    """Liveness. Answers as long as the event loop can serve a request."""
    return LivenessResponse(status="alive")


@router.get(
    "/ready",
    response_model=ReadinessResponse,
    responses={status.HTTP_503_SERVICE_UNAVAILABLE: {"model": ReadinessResponse}},
)
async def ready(response: Response) -> ReadinessResponse:
    """Readiness. Verifies every datastore this service depends on.

    Both dependencies are checked on every call rather than cached, so a
    datastore that becomes unreachable is reflected within one probe period.
    """
    statuses = await datastores.check_all()
    dependencies = [
        DependencyHealth(name=item.name, healthy=item.healthy, detail=item.detail)
        for item in statuses
    ]
    ready_now = all(item.healthy for item in statuses)

    if not ready_now:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    return ReadinessResponse(
        status="ready" if ready_now else "not_ready",
        dependencies=dependencies,
    )
