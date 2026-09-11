"""Local SignDemo training backend.

This service is intentionally small and predictable. It is for the local
SignDemo app only; do not point it at real accounts or production traffic.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import time
from dataclasses import dataclass
from threading import Lock, Thread
from typing import Any

from flask import Flask, jsonify, request
from flask_sock import Sock
from simple_websocket import ConnectionClosed


DEFAULT_SECRET = "local-demo-secret-v1"
DEFAULT_TIME_WINDOW_SECONDS = 300


@dataclass(frozen=True)
class DemoUser:
    user_id: str
    password: str
    display_name: str


DEMO_USERS: dict[str, DemoUser] = {
    "demo-user-001": DemoUser(
        user_id="demo-user-001",
        password="demo-password",
        display_name="Demo User",
    ),
    "demo-user-002": DemoUser(
        user_id="demo-user-002",
        password="demo-password-2",
        display_name="Second Demo User",
    ),
}


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def _env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _cert_paths() -> tuple[str, str]:
    base = os.path.dirname(os.path.abspath(__file__))
    return (
        os.path.join(base, "certs", "server.crt"),
        os.path.join(base, "certs", "server.key"),
    )


def create_app(
    *,
    secret: str | None = None,
    time_window_seconds: int | None = None,
    testing: bool = False,
) -> Flask:
    """Create the Flask app.

    Parameters are injectable so the test suite can use a short time window
    without changing the normal local configuration.
    """

    app = Flask(__name__)
    app.config.update(
        SIGNING_SECRET=secret or os.getenv("SIGNDEMO_SECRET", DEFAULT_SECRET),
        TIME_WINDOW_SECONDS=(
            time_window_seconds
            if time_window_seconds is not None
            else _env_int("SIGNDEMO_TIME_WINDOW", DEFAULT_TIME_WINDOW_SECONDS)
        ),
        TESTING=testing,
        WS_INTERVAL_SECONDS=_env_int("SIGNDEMO_WS_INTERVAL", 5),
        DEFECT_SKIP_SIGN=_env_flag("SIGNDEMO_DEFECT_SKIP_SIGN", False),
        DEFECT_SKIP_NONCE=_env_flag("SIGNDEMO_DEFECT_SKIP_NONCE", False),
        DEFECT_SKIP_WINDOW=_env_flag("SIGNDEMO_DEFECT_SKIP_WINDOW", False),
        DEFECT_SKIP_ACL=_env_flag("SIGNDEMO_DEFECT_SKIP_ACL", False),
    )

    sock = Sock(app)

    for defect in ("SKIP_SIGN", "SKIP_NONCE", "SKIP_WINDOW", "SKIP_ACL"):
        if app.config[f"DEFECT_{defect}"]:
            print(f"defect {defect.lower()} enabled")

    # This is deliberately process-local for the first learning stage.
    # Restarting the server clears the set; persistence is a later exercise.
    used_nonces: set[str] = set()
    nonce_lock = Lock()
    issued_tokens: dict[str, str] = {}
    stored_orders: dict[str, dict[str, Any]] = {}
    store_lock = Lock()

    def error(message: str, status: int):
        return jsonify({"ok": False, "error": message}), status

    def json_body() -> dict[str, Any] | None:
        body = request.get_json(silent=True)
        return body if isinstance(body, dict) else None

    def canonical_string(body: dict[str, Any], action: str) -> str:
        """Build the exact string shared by App and backend."""

        return (
            f"user_id={body.get('user_id', '')}"
            f"&timestamp={body.get('timestamp', '')}"
            f"&nonce={body.get('nonce', '')}"
            f"&action={action}"
        )

    def expected_signature(body: dict[str, Any], action: str) -> str:
        canonical = canonical_string(body, action)
        digest = hmac.new(
            app.config["SIGNING_SECRET"].encode("utf-8"),
            canonical.encode("utf-8"),
            hashlib.sha256,
        )
        return digest.hexdigest()

    def validate_signed_request(
        body: dict[str, Any] | None,
        action: str,
    ) -> tuple[dict[str, Any] | None, tuple[Any, int] | None]:
        if body is None:
            return None, error("request body must be a JSON object", 400)

        skip_sign = app.config["DEFECT_SKIP_SIGN"]
        skip_nonce = app.config["DEFECT_SKIP_NONCE"]
        skip_window = app.config["DEFECT_SKIP_WINDOW"]

        required = ["user_id", "timestamp", "nonce"]
        if not skip_sign:
            required.append("sign")
        missing = [field for field in required if field not in body]
        if missing:
            return None, error(f"missing fields: {', '.join(missing)}", 400)

        user_id = body["user_id"]
        nonce = body["nonce"]
        supplied_signature = body.get("sign", "")

        if not isinstance(user_id, str) or not user_id:
            return None, error("user_id must be a non-empty string", 400)
        if not isinstance(nonce, str) or not nonce:
            return None, error("nonce must be a non-empty string", 400)
        if not skip_sign and (not isinstance(supplied_signature, str) or not supplied_signature):
            return None, error("sign must be a non-empty string", 400)

        try:
            timestamp = int(body["timestamp"])
        except (TypeError, ValueError):
            return None, error("timestamp must be an integer Unix timestamp", 400)

        now = int(time.time())
        if not skip_window and abs(now - timestamp) > app.config["TIME_WINDOW_SECONDS"]:
            return None, error("request timestamp is outside the allowed window", 401)

        if not skip_sign:
            expected = expected_signature(body, action)
            if not hmac.compare_digest(str(supplied_signature).lower(), expected):
                return None, error("invalid signature", 401)

        if not skip_nonce:
            with nonce_lock:
                if nonce in used_nonces:
                    return None, error("nonce has already been used", 409)
                used_nonces.add(nonce)

        return body, None

    def issue_token(user_id: str) -> str:
        # This token is only a local demo value. It is not a production token.
        return f"demo-token-{user_id}-{secrets.token_hex(8)}"

    def bearer_user_id() -> str | None:
        header = request.headers.get("Authorization") or ""
        if not header.lower().startswith("bearer "):
            return None
        token = header[7:].strip()
        if not token:
            return None
        with store_lock:
            return issued_tokens.get(token)

    @app.get("/api/health")
    def health():
        return jsonify(
            {
                "ok": True,
                "service": "SignDemo",
                "time": int(time.time()),
            }
        )

    @app.post("/api/login")
    def login():
        body, failure = validate_signed_request(json_body(), "login")
        if failure is not None:
            return failure

        assert body is not None
        user = DEMO_USERS.get(body["user_id"])
        if user is None or body.get("password") != user.password:
            return error("invalid demo credentials", 401)

        token = issue_token(user.user_id)
        with store_lock:
            issued_tokens[token] = user.user_id
        return jsonify(
            {
                "ok": True,
                "user_id": user.user_id,
                "display_name": user.display_name,
                "token": token,
            }
        )

    @app.post("/api/order")
    def create_order():
        body, failure = validate_signed_request(json_body(), "order")
        if failure is not None:
            return failure

        assert body is not None
        order_id = body.get("order_id")
        amount = body.get("amount")
        if not isinstance(order_id, str) or not order_id:
            return error("order_id must be a non-empty string", 400)
        if not isinstance(amount, (int, float)) or isinstance(amount, bool):
            return error("amount must be a number", 400)
        if amount <= 0:
            return error("amount must be greater than zero", 400)

        order = {
            "order_id": order_id,
            "user_id": body["user_id"],
            "amount": amount,
            "status": "created",
        }
        with store_lock:
            stored_orders[order_id] = order
        return jsonify({"ok": True, "order": order})

    @app.get("/api/orders/<order_id>")
    def get_order(order_id: str):
        skip_acl = app.config["DEFECT_SKIP_ACL"]
        actor = None
        if not skip_acl:
            actor = bearer_user_id()
            if actor is None:
                return error("missing or invalid token", 401)
        with store_lock:
            order = stored_orders.get(order_id)
        if order is None:
            return error("order not found", 404)
        if not skip_acl and order["user_id"] != actor:
            return error("forbidden", 403)
        return jsonify({"ok": True, "order": order})

    @sock.route("/ws/events")
    def ws_events(ws):
        token = (request.args.get("token") or "").strip()
        if not token:
            ws.send(json.dumps({"ok": False, "error": "missing token"}))
            return

        print(f"SignDemo WS connected token={token[:32]}")
        interval = max(1, int(app.config["WS_INTERVAL_SECONDS"]))
        try:
            while True:
                ws.send(
                    json.dumps(
                        {
                            "ok": True,
                            "type": "tick",
                            "service": "SignDemo",
                            "time": int(time.time()),
                        }
                    )
                )
                deadline = time.time() + interval
                while time.time() < deadline:
                    time.sleep(0.2)
        except (ConnectionClosed, OSError, BrokenPipeError):
            print("SignDemo WS disconnected")

    @app.get("/api/profile/<user_id>")
    def profile(user_id: str):
        skip_acl = app.config["DEFECT_SKIP_ACL"]
        if not skip_acl:
            actor = bearer_user_id()
            if actor is None:
                return error("missing or invalid token", 401)
            if actor != user_id:
                return error("forbidden", 403)
        user = DEMO_USERS.get(user_id)
        if user is None:
            return error("demo user not found", 404)
        return jsonify(
            {
                "ok": True,
                "profile": {
                    "user_id": user.user_id,
                    "display_name": user.display_name,
                },
            }
        )

    return app


app = create_app()


def run_local_servers() -> None:
    """Serve HTTP :5000 and, when certs exist, HTTPS :5443 together."""

    host = os.getenv("SIGNDEMO_HOST", "0.0.0.0")
    http_port = _env_int("SIGNDEMO_PORT", 5000)
    https_port = _env_int("SIGNDEMO_HTTPS_PORT", 5443)
    enable_https = _env_flag("SIGNDEMO_TLS", True)
    cert_path, key_path = _cert_paths()
    have_certs = os.path.isfile(cert_path) and os.path.isfile(key_path)

    def serve(port: int, ssl_context: tuple[str, str] | None) -> None:
        scheme = "https" if ssl_context else "http"
        print(f"SignDemo {scheme}://{host}:{port}")
        app.run(
            host=host,
            port=port,
            debug=False,
            use_reloader=False,
            threaded=True,
            ssl_context=ssl_context,
        )

    if enable_https and have_certs:
        http_thread = Thread(
            target=serve,
            args=(http_port, None),
            name="sign-demo-http",
            daemon=True,
        )
        http_thread.start()
        serve(https_port, (cert_path, key_path))
        return

    if enable_https and not have_certs:
        print("未找到 certs/server.crt 或 certs/server.key，只启动 HTTP")

    serve(http_port, None)


if __name__ == "__main__":
    run_local_servers()
