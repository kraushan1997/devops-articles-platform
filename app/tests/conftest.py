"""Test fixtures.

The API talks to MongoDB through pymongo's AsyncCollection. For unit tests we swap
in a thin async wrapper around mongomock's in-memory collection, so the suite runs
without a database (integration against a real replica set is covered by
scripts/test-api.sh against the deployed service).
"""
import os

os.environ.setdefault("MONGO_TIMEOUT_MS", "50")

import mongomock  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from articles_api.main import app  # noqa: E402


class _AsyncCursor:
    def __init__(self, cursor):
        self._cursor = cursor

    def sort(self, *a, **kw):
        self._cursor = self._cursor.sort(*a, **kw)
        return self

    def skip(self, n):
        self._cursor = self._cursor.skip(n)
        return self

    def limit(self, n):
        self._cursor = self._cursor.limit(n)
        return self

    def __aiter__(self):
        self._it = iter(self._cursor)
        return self

    async def __anext__(self):
        try:
            return next(self._it)
        except StopIteration:
            raise StopAsyncIteration


class AsyncCollection:
    def __init__(self, coll):
        self._c = coll

    def find(self, *a, **kw):
        return _AsyncCursor(self._c.find(*a, **kw))

    def __getattr__(self, name):
        fn = getattr(self._c, name)

        async def _call(*a, **kw):
            return fn(*a, **kw)

        return _call


@pytest.fixture()
def client():
    with TestClient(app) as c:
        app.state.collection = AsyncCollection(mongomock.MongoClient()["test"]["articles"])
        yield c
