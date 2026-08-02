"""OpenTelemetry tracing, disabled unless a collector endpoint is configured.

Tracing is off by default on purpose. The OTLP exporter retries on failure, so
enabling it before a collector exists produces a steady stream of connection
errors in every replica and no traces. The code lands in this phase; Phase 7
sets OTEL_EXPORTER_OTLP_ENDPOINT once Alloy is receiving OTLP, and tracing
begins with no further code change.

Instrumentation covers the three hops that matter for this service: the inbound
HTTP request, the PostgreSQL query, and the Redis command.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI

from app.core.config import settings

logger = logging.getLogger(__name__)


def is_enabled() -> bool:
    return bool(settings.otel_exporter_otlp_endpoint)


def initialise(app: FastAPI) -> None:
    """Wire tracing if an endpoint is configured, otherwise do nothing.

    Import failures are reported and swallowed. A missing or incompatible
    tracing dependency must never stop the service from serving traffic;
    losing observability is bad, losing the service is worse.
    """
    if not is_enabled():
        logger.info("Tracing disabled: no OTLP endpoint configured.")
        return

    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
            OTLPSpanExporter,
        )
        from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.redis import RedisInstrumentor
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased
    except ImportError:
        logger.exception("Tracing requested but the dependencies are unavailable.")
        return

    resource = Resource.create(
        {
            "service.name": settings.otel_service_name,
            "service.version": settings.app_version,
            "deployment.environment": settings.environment,
        }
    )

    # Head sampling. The node stores traces on a 1.5Gi local volume, so a
    # fraction is retained rather than everything. ParentBased keeps a trace
    # whole: once the edge decides to sample a request, every downstream span
    # for it is kept, which is what makes a sampled trace readable.
    provider = TracerProvider(
        resource=resource,
        sampler=ParentBased(TraceIdRatioBased(settings.otel_traces_sample_ratio)),
    )
    provider.add_span_processor(
        BatchSpanProcessor(
            OTLPSpanExporter(
                endpoint=f"{settings.otel_exporter_otlp_endpoint}/v1/traces"
            )
        )
    )
    trace.set_tracer_provider(provider)

    # The scrape endpoint would otherwise produce a span every fifteen seconds
    # per replica, which is pure noise.
    FastAPIInstrumentor.instrument_app(
        app,
        excluded_urls=f"{settings.metrics_path},/live,/ready",
    )
    AsyncPGInstrumentor().instrument()
    RedisInstrumentor().instrument()

    logger.info(
        "Tracing enabled: endpoint=%s sample_ratio=%s",
        settings.otel_exporter_otlp_endpoint,
        settings.otel_traces_sample_ratio,
    )
