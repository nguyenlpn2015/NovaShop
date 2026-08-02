FROM python:3.12.13-slim-bookworm AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /build
COPY pyproject.toml ./
COPY app ./app
RUN pip wheel --wheel-dir /wheels .

FROM python:3.12.13-slim-bookworm AS runtime

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PATH="/home/novashop/.local/bin:${PATH}"

RUN groupadd --system --gid 10001 novashop \
    && useradd --system --uid 10001 --gid novashop --create-home novashop

COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/* \
    && rm -rf /wheels

WORKDIR /app

# Migrations ship in the image so the Job that runs them is the same artefact as
# the application it migrates. A separate migration image can drift from the code
# it is supposed to match, and the drift is invisible until a deploy half-applies.
#
# The wheel carries `app`; these are data files it does not include. --chown
# because COPY runs as root regardless of USER.
COPY --chown=novashop:novashop alembic.ini ./
COPY --chown=novashop:novashop alembic ./alembic

USER novashop

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
