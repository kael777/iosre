from __future__ import annotations

import hashlib
import hmac
import time

import pytest

from app import create_app


SECRET = "test-secret"


def make_signature(
    *,
    user_id: str,
    timestamp: int,
    nonce: str,
    action: str,
) -> str:
    canonical = (
        f"user_id={user_id}"
        f"&timestamp={timestamp}"
        f"&nonce={nonce}"
        f"&action={action}"
    )
    return hmac.new(
        SECRET.encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


@pytest.fixture()
def client():
    app = create_app(secret=SECRET, testing=True)
    with app.test_client() as test_client:
        yield test_client


def signed_body(*, action: str, nonce: str, **extra):
    timestamp = int(time.time())
    body = {
        "user_id": "demo-user-001",
        "timestamp": timestamp,
        "nonce": nonce,
        "sign": make_signature(
            user_id="demo-user-001",
            timestamp=timestamp,
            nonce=nonce,
            action=action,
        ),
    }
    body.update(extra)
    return body


def test_health(client):
    response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json["ok"] is True
    assert response.json["service"] == "SignDemo"


def test_login_accepts_valid_signature(client):
    response = client.post(
        "/api/login",
        json=signed_body(
            action="login",
            nonce="login-valid-001",
            password="demo-password",
        ),
    )

    assert response.status_code == 200
    assert response.json["ok"] is True
    assert response.json["user_id"] == "demo-user-001"
    assert response.json["token"].startswith("demo-token-demo-user-001-")


def test_modified_field_without_new_signature_is_rejected(client):
    body = signed_body(
        action="login",
        nonce="login-modified-001",
        password="demo-password",
    )
    body["user_id"] = "demo-user-002"

    response = client.post("/api/login", json=body)

    assert response.status_code == 401
    assert response.json["error"] == "invalid signature"


def test_expired_timestamp_is_rejected(client):
    timestamp = int(time.time()) - 301
    body = {
        "user_id": "demo-user-001",
        "password": "demo-password",
        "timestamp": timestamp,
        "nonce": "login-expired-001",
        "sign": make_signature(
            user_id="demo-user-001",
            timestamp=timestamp,
            nonce="login-expired-001",
            action="login",
        ),
    }

    response = client.post("/api/login", json=body)

    assert response.status_code == 401
    assert response.json["error"] == "request timestamp is outside the allowed window"


def test_nonce_cannot_be_reused(client):
    body = signed_body(
        action="login",
        nonce="login-replay-001",
        password="demo-password",
    )

    first = client.post("/api/login", json=body)
    second = client.post("/api/login", json=body)

    assert first.status_code == 200
    assert second.status_code == 409
    assert second.json["error"] == "nonce has already been used"


def test_order_accepts_valid_signature(client):
    response = client.post(
        "/api/order",
        json=signed_body(
            action="order",
            nonce="order-valid-001",
            order_id="order-001",
            amount=10,
        ),
    )

    assert response.status_code == 200
    assert response.json["ok"] is True
    assert response.json["order"]["status"] == "created"
    assert response.json["order"]["amount"] == 10


def test_order_rejects_non_positive_amount(client):
    response = client.post(
        "/api/order",
        json=signed_body(
            action="order",
            nonce="order-invalid-001",
            order_id="order-001",
            amount=0,
        ),
    )

    assert response.status_code == 400
    assert response.json["error"] == "amount must be greater than zero"
