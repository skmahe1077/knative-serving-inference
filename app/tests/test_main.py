import pytest
from fastapi.testclient import TestClient

from main import app


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readyz_after_startup(client):
    response = client.get("/readyz")
    assert response.status_code == 200


def test_predict(client):
    response = client.post("/predict", json={"features": [5.1, 3.5, 1.4, 0.2]})
    assert response.status_code == 200
    body = response.json()
    assert body["predicted_class"] in {"setosa", "versicolor", "virginica"}
    assert abs(sum(body["probabilities"].values()) - 1.0) < 1e-3


def test_predict_rejects_wrong_feature_count(client):
    response = client.post("/predict", json={"features": [1.0, 2.0]})
    assert response.status_code == 422


def test_metrics_exposed(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"http_requests_total" in response.content or b"# HELP" in response.content
