#!/usr/bin/env python3
"""Generate and send requests to the local SignDemo backend."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import secrets
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_BASE_URL = "http://127.0.0.1:5000"
DEFAULT_SECRET = "local-demo-secret-v1"


def make_signature(
    *,
    secret: str,
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
        secret.encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def send_json(url: str, body: dict) -> None:
    payload = json.dumps(body).encode("utf-8")
    request = Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=5) as response:
            print(f"HTTP {response.status}")
            print(response.read().decode("utf-8"))
    except HTTPError as exc:
        print(f"HTTP {exc.code}")
        print(exc.read().decode("utf-8"))
    except URLError as exc:
        raise SystemExit(f"无法连接后端：{exc.reason}") from exc


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "action",
        choices=("login", "order"),
        help="要发送的本地接口",
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help="后端地址，真机测试时改为 Mac 局域网 IP",
    )
    parser.add_argument("--secret", default=DEFAULT_SECRET)
    parser.add_argument("--user-id", default="demo-user-001")
    parser.add_argument("--password", default="demo-password")
    parser.add_argument("--order-id", default="order-001")
    parser.add_argument("--amount", type=float, default=10)
    args = parser.parse_args()

    timestamp = int(time.time())
    nonce = secrets.token_hex(8)
    body = {
        "user_id": args.user_id,
        "timestamp": timestamp,
        "nonce": nonce,
        "sign": make_signature(
            secret=args.secret,
            user_id=args.user_id,
            timestamp=timestamp,
            nonce=nonce,
            action=args.action,
        ),
    }

    if args.action == "login":
        body["password"] = args.password
    else:
        body["order_id"] = args.order_id
        body["amount"] = args.amount

    print("request:", json.dumps(body, ensure_ascii=False))
    send_json(f"{args.base_url.rstrip('/')}/api/{args.action}", body)


if __name__ == "__main__":
    main()
