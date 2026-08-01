from fastapi.testclient import TestClient

from app.main import app


def test_health() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_live_is_independent_of_dependencies() -> None:
    """Liveness must answer even with no datastore reachable.

    The test environment has neither PostgreSQL nor Redis, which is exactly the
    condition under which liveness must not fail: a failing liveness probe
    restarts the container, and a restart cannot fix a datastore outage.
    """
    with TestClient(app) as client:
        response = client.get("/live")

    assert response.status_code == 200
    assert response.json() == {"status": "alive"}


def test_ready_reports_unavailable_dependencies() -> None:
    """Readiness must fail closed when a dependency cannot be reached."""
    with TestClient(app) as client:
        response = client.get("/ready")

    assert response.status_code == 503

    payload = response.json()
    assert payload["status"] == "not_ready"

    reported = {item["name"]: item for item in payload["dependencies"]}
    assert set(reported) == {"postgresql", "redis"}
    assert all(item["healthy"] is False for item in reported.values())


def test_ready_never_leaks_the_connection_string() -> None:
    """Failure detail identifies the fault without exposing credentials."""
    with TestClient(app) as client:
        body = client.get("/ready").text

    assert "password" not in body.lower()
    assert "@" not in body
