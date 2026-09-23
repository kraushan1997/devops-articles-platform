ARTICLE = {"title": "Hello", "content": "World", "author": "raushan", "tags": ["k8s"]}


def test_healthz(client):
    assert client.get("/healthz").json() == {"status": "ok"}


def test_readyz_fails_without_db(client):
    # No MongoDB in unit tests -> readiness must report 503, liveness stays 200
    assert client.get("/readyz").status_code == 503


def test_crud_lifecycle(client):
    r = client.post("/articles", json=ARTICLE)
    assert r.status_code == 201
    art = r.json()
    aid = art["id"]
    assert art["title"] == "Hello"

    assert client.get(f"/articles/{aid}").json()["author"] == "raushan"
    assert len(client.get("/articles").json()) == 1

    r = client.put(f"/articles/{aid}", json={"title": "Updated"})
    assert r.status_code == 200
    assert r.json()["title"] == "Updated"
    assert r.json()["content"] == "World"  # untouched fields preserved

    assert client.delete(f"/articles/{aid}").status_code == 204
    assert client.get(f"/articles/{aid}").status_code == 404
    assert client.get("/articles").json() == []


def test_list_pagination(client):
    for i in range(5):
        client.post("/articles", json=ARTICLE | {"title": f"t{i}"})
    assert len(client.get("/articles?limit=2").json()) == 2
    assert len(client.get("/articles?skip=4").json()) == 1
    assert client.get("/articles?limit=0").status_code == 422


def test_validation_and_not_found(client):
    assert client.post("/articles", json={"title": ""}).status_code == 422
    assert client.get("/articles/not-an-id").status_code == 404
    missing = "64b7f0000000000000000000"
    assert client.get(f"/articles/{missing}").status_code == 404
    assert client.delete(f"/articles/{missing}").status_code == 404
    assert client.put(f"/articles/{missing}", json={"title": "x"}).status_code == 404
    assert client.put(f"/articles/{missing}", json={}).status_code == 400


def test_metrics_exposed(client):
    client.get("/articles")
    assert "http_requests_total" in client.get("/metrics").text
