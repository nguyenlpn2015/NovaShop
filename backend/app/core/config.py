from functools import lru_cache

from pydantic import PostgresDsn, RedisDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "NovaShop API"
    app_version: str = "0.1.0"
    environment: str = "development"
    log_level: str = "INFO"
    database_url: PostgresDsn = PostgresDsn(
        "postgresql://novashop:novashop@postgres:5432/novashop"
    )
    redis_url: RedisDsn = RedisDsn("redis://redis:6379/0")
    # Readiness probes are the only current consumer, so the pool stays small.
    # Three replicas per environment must not exhaust the server's connection
    # slots just by being probed.
    database_pool_max_size: int = 2

    # Metrics are always on. The endpoint is publicly reachable, because the
    # backend Ingress routes the "/" prefix and every path this application
    # serves is therefore exposed. Prometheus does not use that route -- it
    # scrapes the pod directly. See docs/security/hardening.md for the remedy.
    metrics_path: str = "/metrics"

    # Tracing stays off. The OTLP exporter retries on failure, so enabling it
    # without a collector produces errors in every replica and no traces.
    # ADR 011 records the decision not to deploy one, and the conditions that
    # would reverse it. Setting this variable is all that enabling requires.
    otel_exporter_otlp_endpoint: str = ""
    otel_service_name: str = "novashop-backend"
    otel_traces_sample_ratio: float = 0.1


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
