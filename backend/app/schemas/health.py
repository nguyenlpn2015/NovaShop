from typing import Literal

from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: Literal["healthy"]
    service: str
    version: str


class LivenessResponse(BaseModel):
    """Process liveness. Deliberately carries no dependency state.

    Kubernetes restarts a container whose liveness probe fails. Reporting a
    datastore outage here would restart every replica during an outage the
    restart cannot fix, turning a degraded service into an unavailable one.
    """

    status: Literal["alive"]


class DependencyHealth(BaseModel):
    name: str
    healthy: bool
    detail: str | None = None


class ReadinessResponse(BaseModel):
    """Whether this replica should receive traffic.

    Returned with HTTP 503 when any dependency is unhealthy, which removes the
    replica from the Service endpoints without restarting it.
    """

    status: Literal["ready", "not_ready"]
    dependencies: list[DependencyHealth]
