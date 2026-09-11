#!/usr/bin/env python3
"""Reproduce SignDemo POST /api/order against the local backend only.

Generates a fresh nonce. Do not reuse a nonce from the App or from login.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _local import (
    DEFAULT_BASE_URL,
    DEFAULT_SECRET,
    DEFAULT_USER_ID,
    post_json,
    signed_body,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="本地复现 /api/order，虚构测试订单")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--secret", default=DEFAULT_SECRET)
    parser.add_argument("--user-id", default=DEFAULT_USER_ID)
    parser.add_argument("--order-id", default="order-001")
    parser.add_argument("--amount", type=float, default=10)
    parser.add_argument("--bad-timestamp", action="store_true", help="timestamp=1，预期 401")
    parser.add_argument("--bad-sign", action="store_true", help="错误 sign，预期 401")
    parser.add_argument("--reuse-nonce", action="store_true", help="同一 nonce 发两次，第二次预期 409")
    args = parser.parse_args()

    timestamp = 1 if args.bad_timestamp else None
    body, nonce = signed_body(
        secret=args.secret,
        user_id=args.user_id,
        action="order",
        timestamp=timestamp,
        bad_sign=args.bad_sign,
    )
    body["order_id"] = args.order_id
    body["amount"] = args.amount

    url = f"{args.base_url.rstrip('/')}/api/order"
    print("canonical action=order")
    print("request:", json.dumps(body, ensure_ascii=False))
    status, parsed = post_json(url, body)
    print(f"HTTP {status}")
    print(json.dumps(parsed, ensure_ascii=False, indent=2) if isinstance(parsed, dict) else parsed)

    if args.reuse_nonce:
        print("--- reuse same nonce ---")
        again = dict(body)
        again["nonce"] = nonce
        status2, parsed2 = post_json(url, again)
        print(f"HTTP {status2}")
        print(json.dumps(parsed2, ensure_ascii=False, indent=2) if isinstance(parsed2, dict) else parsed2)
        reused_failed = isinstance(parsed2, dict) and parsed2.get("ok") is not True
        first_ok = isinstance(parsed, dict) and parsed.get("ok") is True
        if first_ok and reused_failed:
            print("order ok; replay rejected")
            return 0
        print("reuse-nonce check failed")
        return 1

    if isinstance(parsed, dict) and parsed.get("ok") is True:
        print("order ok")
        return 0

    print("order failed")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
