# syntax=docker/dockerfile:1.7
# ---- build stage: compile wheels so the runtime image has no compiler/toolchain
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---- runtime stage
FROM python:3.12-slim
LABEL org.opencontainers.image.source="https://github.com/kraushan1997/devops-articles-platform" \
      org.opencontainers.image.description="Articles REST API (FastAPI + MongoDB)"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

# Fixed non-root UID so Kubernetes runAsNonRoot / runAsUser can be enforced
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app

COPY --from=build /wheels /wheels
RUN pip install --no-cache-dir /wheels/* && rm -rf /wheels

WORKDIR /app
COPY src ./src

USER 10001
EXPOSE 8080

# Container-level healthcheck for docker/compose; Kubernetes uses its own probes
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz').status==200 else 1)"

CMD ["uvicorn", "articles_api.main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers", "--no-server-header"]
