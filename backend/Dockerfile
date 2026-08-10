FROM python:3.14.7-slim-bookworm AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /build
COPY pyproject.toml ./
COPY app ./app
RUN pip wheel --wheel-dir /wheels .

FROM python:3.14.7-slim-bookworm AS runtime

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PATH="/home/novashop/.local/bin:${PATH}"

RUN groupadd --system --gid 10001 novashop \
    && useradd --system --uid 10001 --gid novashop --create-home novashop

COPY --from=builder /wheels /wheels
# pip is a build tool, and nothing in this image runs it after the wheels are
# installed: the entrypoint is uvicorn and migrations run through alembic.
#
# Removing it is not housekeeping. pip carries its dependencies vendored inside
# pip/_vendor, and those copies are scanned like any other package: on
# python:3.14.7-slim-bookworm they are msgpack 1.1.2 (GHSA-6v7p-g79w-8964) and
# setuptools 70.3.0 (CVE-2025-47273), both HIGH and both unfixable from here
# because neither is a dependency we declare or can upgrade. Uninstalling pip is
# what actually removes the code, rather than suppressing the finding.
RUN pip install --no-cache-dir /wheels/* \
    && rm -rf /wheels \
    && python -m pip uninstall --yes pip

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
