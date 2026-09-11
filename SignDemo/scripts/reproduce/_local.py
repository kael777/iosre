"""Shared helpers for SignDemo local reproduce scripts.

Only talks to 127.0.0.1 or a private LAN IP. Not for third-party hosts.
"""

from __future__ import annotations

import hashlib
import hmac
import ipaddress
import json
import secrets
import ssl
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

DEFAULT_BASE_URL = "https://127.0.0.1:5443"
DEFAULT_SECRET = "local-demo-secret-v1"
DEFAULT_USER_ID = "demo-user-001"
DEFAULT_PASSWORD = "demo-password"

ROOT = Path(__file__).resolve().parents[2]
CA_PATH = ROOT / "backend" / "certs" / "ca.crt"


def make_signature(*, secret: str, user_id: str, timestamp: int, nonce: str, action: str) -> str:
    canonical = (
        f"user_id={user_id}"
        f"&timestamp={timestamp}"
        f"&nonce={nonce}"
        f"&action={action}"
    )
    return hmac.new(
        secret.encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def signed_body(*, secret: str, user_id: str, action: str, timestamp: int | None = None, nonce: str | None = None, bad_sign: bool = False) -> tuple[dict, str]:
    ts = int(time.time()) if timestamp is None else timestamp
    nonce_value = nonce or secrets.token_hex(8)
    sign = make_signature(
        secret=secret,
        user_id=user_id,
        timestamp=ts,
        nonce=nonce_value,
        action=action,
    )
    if bad_sign:
        sign = "0" * 64
    body = {
        "user_id": user_id,
        "timestamp": ts,
        "nonce": nonce_value,
        "sign": sign,
    }
    return body, nonce_value


def assert_local_url(base_url: str) -> None:
    parsed = urlparse(base_url)
    host = (parsed.hostname or "").lower()
    if host in {"127.0.0.1", "localhost"}:
        return
    try:
        address = ipaddress.ip_address(host)
    except ValueError as exc:
        raise SystemExit(f"只允许 127.0.0.1 或局域网 IP，当前 host={host!r}") from exc
    if not address.is_private:
        raise SystemExit(f"拒绝非本地地址：{host}")


def ssl_context(url: str) -> ssl.SSLContext | None:
    if not url.lower().startswith("https://"):
        return None
    if not CA_PATH.is_file():
        raise SystemExit(f"找不到练习 CA：{CA_PATH}")
    context = ssl.create_default_context(cafile=str(CA_PATH))
    # 练习 CA 未带 keyUsage；Python 3.14 默认 VERIFY_X509_STRICT 会拒绝。
    if hasattr(ssl, "VERIFY_X509_STRICT"):
        context.verify_flags &= ~ssl.VERIFY_X509_STRICT
    context.check_hostname = False
    return context


def post_json(url: str, body: dict) -> tuple[int, dict | str]:
    assert_local_url(url)
    payload = json.dumps(body).encode("utf-8")
    request = Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=8, context=ssl_context(url)) as response:
            raw = response.read().decode("utf-8")
            status = response.status
    except HTTPError as exc:
        raw = exc.read().decode("utf-8")
        status = exc.code
    except URLError as exc:
        raise SystemExit(f"无法连接后端：{exc.reason}") from exc

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = raw
    return status, parsed
