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


def signed_body(*, action: str, nonce: str, user_id: str = "demo-user-001", **extra):
    timestamp = int(time.time())
    body = {
        "user_id": user_id,
        "timestamp": timestamp,
        "nonce": nonce,
        "sign": make_signature(
            user_id=user_id,
            timestamp=timestamp,
            nonce=nonce,
            action=action,
        ),
    }
    body.update(extra)
    return body


def login(client, *, user_id: str, password: str, nonce: str) -> str:
    response = client.post(
        "/api/login",
        json=signed_body(
            action="login",
            nonce=nonce,
            user_id=user_id,
            password=password,
        ),
    )
    assert response.status_code == 200
    return response.json["token"]


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


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


def test_owner_can_read_own_order(client):
    token = login(
        client,
        user_id="demo-user-001",
        password="demo-password",
        nonce="login-owner-001",
    )
    created = client.post(
        "/api/order",
        json=signed_body(
            action="order",
            nonce="order-store-001",
            order_id="order-a",
            amount=10,
        ),
    )
    fetched = client.get("/api/orders/order-a", headers=auth_header(token))

    assert created.status_code == 200
    assert fetched.status_code == 200
    assert fetched.json["order"]["user_id"] == "demo-user-001"
    assert fetched.json["order"]["amount"] == 10


def test_order_read_without_token_is_401(client):
    client.post(
        "/api/order",
        json=signed_body(
            action="order",
            nonce="order-unauth-001",
            order_id="order-a",
            amount=10,
        ),
    )
    fetched = client.get("/api/orders/order-a")

    assert fetched.status_code == 401
    assert fetched.json["error"] == "missing or invalid token"


def test_other_user_cannot_read_order(client):
    token_a = login(
        client,
        user_id="demo-user-001",
        password="demo-password",
        nonce="login-idor-a",
    )
    token_b = login(
        client,
        user_id="demo-user-002",
        password="demo-password-2",
        nonce="login-idor-b",
    )
    client.post(
        "/api/order",
        json=signed_body(
            action="order",
            nonce="order-idor-b",
            user_id="demo-user-002",
            order_id="order-b",
            amount=99,
        ),
    )
    stolen = client.get("/api/orders/order-b", headers=auth_header(token_a))
    own = client.get("/api/orders/order-b", headers=auth_header(token_b))

    assert stolen.status_code == 403
    assert stolen.json["error"] == "forbidden"
    assert own.status_code == 200
    assert own.json["order"]["user_id"] == "demo-user-002"
    assert own.json["order"]["amount"] == 99


def test_missing_order_is_404_when_authenticated(client):
    token = login(
        client,
        user_id="demo-user-001",
        password="demo-password",
        nonce="login-missing-001",
    )
    response = client.get("/api/orders/does-not-exist", headers=auth_header(token))

    assert response.status_code == 404
    assert response.json["error"] == "order not found"


def test_profile_rejects_other_user(client):
    token_a = login(
        client,
        user_id="demo-user-001",
        password="demo-password",
        nonce="login-profile-a",
    )
    other = client.get("/api/profile/demo-user-002", headers=auth_header(token_a))
    own = client.get("/api/profile/demo-user-001", headers=auth_header(token_a))
    missing = client.get("/api/profile/demo-user-002")

    assert other.status_code == 403
    assert own.status_code == 200
    assert own.json["profile"]["user_id"] == "demo-user-001"
    assert missing.status_code == 401


def test_skip_acl_allows_cross_user_read(monkeypatch):
    monkeypatch.setenv("SIGNDEMO_DEFECT_SKIP_ACL", "1")
    app = create_app(secret=SECRET, testing=True)
    with app.test_client() as client:
        token_a = login(
            client,
            user_id="demo-user-001",
            password="demo-password",
            nonce="login-skip-acl-a",
        )
        client.post(
            "/api/order",
            json=signed_body(
                action="order",
                nonce="order-skip-acl-b",
                user_id="demo-user-002",
                order_id="order-b",
                amount=99,
            ),
        )
        stolen = client.get("/api/orders/order-b", headers=auth_header(token_a))
        anonymous = client.get("/api/orders/order-b")
        profile = client.get("/api/profile/demo-user-002")

        assert stolen.status_code == 200
        assert stolen.json["order"]["user_id"] == "demo-user-002"
        assert stolen.json["order"]["amount"] == 99
        assert anonymous.status_code == 200
        assert profile.status_code == 200
        assert profile.json["profile"]["display_name"] == "Second Demo User"


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
