"""Articles REST API — FastAPI + MongoDB.

Endpoints
---------
POST   /articles        create
GET    /articles        list (supports ?skip=&limit=)
GET    /articles/{id}   read
PUT    /articles/{id}   update (partial fields allowed)
DELETE /articles/{id}   delete

Operational endpoints
---------------------
GET /healthz   liveness  — process is up (never touches the DB, so a DB blip
                           does not cause Kubernetes to restart every pod)
GET /readyz    readiness — MongoDB is reachable; pod is pulled from the
                           Service endpoints while the DB is unreachable
GET /metrics   Prometheus metrics (request count/latency per route)
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import FastAPI, HTTPException, Query, Response, status
from prometheus_fastapi_instrumentator import Instrumentator
from pymongo import AsyncMongoClient, ReturnDocument

from .config import settings
from .models import ArticleCreate, ArticleOut, ArticleUpdate

logging.basicConfig(
    level=settings.log_level,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
)
log = logging.getLogger("articles-api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    client = AsyncMongoClient(
        settings.mongo_uri,
        serverSelectionTimeoutMS=settings.mongo_timeout_ms,
        uuidRepresentation="standard",
        tz_aware=True,  # return UTC-aware datetimes -> ISO timestamps keep their "Z"/offset
        appname="articles-api",
    )
    app.state.mongo = client
    app.state.collection = client[settings.mongo_db][settings.mongo_collection]
    try:
        await app.state.collection.create_index("created_at")
    except Exception as exc:  # DB may not be ready yet; readiness probe covers it
        log.warning("could not create index at startup: %s", exc)
    log.info("started; db=%s collection=%s", settings.mongo_db, settings.mongo_collection)
    yield
    await client.close()


app = FastAPI(title="Articles API", version=settings.app_version, lifespan=lifespan)
Instrumentator(excluded_handlers=["/healthz", "/readyz", "/metrics"]).instrument(app).expose(
    app, include_in_schema=False
)


def _oid(article_id: str) -> ObjectId:
    try:
        return ObjectId(article_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=404, detail="Article not found")


def _out(doc: dict) -> ArticleOut:
    doc["id"] = str(doc.pop("_id"))
    return ArticleOut(**doc)


# ---------------------------------------------------------------- health
@app.get("/healthz", include_in_schema=False)
async def healthz():
    return {"status": "ok"}


@app.get("/readyz", include_in_schema=False)
async def readyz():
    try:
        await app.state.mongo.admin.command("ping")
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"mongodb unavailable: {exc.__class__.__name__}")
    return {"status": "ready"}


# ---------------------------------------------------------------- CRUD
@app.post("/articles", response_model=ArticleOut, status_code=status.HTTP_201_CREATED)
async def create_article(body: ArticleCreate):
    now = datetime.now(timezone.utc)
    doc = body.model_dump() | {"created_at": now, "updated_at": now}
    res = await app.state.collection.insert_one(doc)
    doc["_id"] = res.inserted_id
    return _out(doc)


@app.get("/articles", response_model=list[ArticleOut])
async def list_articles(skip: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=500)):
    cursor = app.state.collection.find().sort("created_at", -1).skip(skip).limit(limit)
    return [_out(d) async for d in cursor]


@app.get("/articles/{article_id}", response_model=ArticleOut)
async def get_article(article_id: str):
    doc = await app.state.collection.find_one({"_id": _oid(article_id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Article not found")
    return _out(doc)


@app.put("/articles/{article_id}", response_model=ArticleOut)
async def update_article(article_id: str, body: ArticleUpdate):
    changes = body.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status_code=400, detail="No fields to update")
    changes["updated_at"] = datetime.now(timezone.utc)
    doc = await app.state.collection.find_one_and_update(
        {"_id": _oid(article_id)}, {"$set": changes}, return_document=ReturnDocument.AFTER
    )
    if not doc:
        raise HTTPException(status_code=404, detail="Article not found")
    return _out(doc)


@app.delete("/articles/{article_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_article(article_id: str):
    res = await app.state.collection.delete_one({"_id": _oid(article_id)})
    if res.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Article not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
