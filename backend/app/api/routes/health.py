from fastapi import APIRouter

from app.core.config import settings
from app.schemas.health import HealthResponse

router = APIRouter(tags=["health"])

# TODO: Add /live for process liveness checks.
# TODO: Add /ready for PostgreSQL and Redis readiness checks.
# TODO: Revisit /health semantics when the service lifecycle is implemented.


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(
        status="healthy",
        service=settings.app_name,
        version=settings.app_version,
    )
