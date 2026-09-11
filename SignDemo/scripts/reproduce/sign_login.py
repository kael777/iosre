#!/usr/bin/env python3
"""Reproduce SignDemo POST /api/login against the local backend only."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _local import (
    DEFAULT_BASE_URL,
    DEFAULT_PASSWORD,
    DEFAULT_SECRET,
    DEFAULT_USER_ID,
    post_json,
    signed_body,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="本地复现 /api/login，虚构测试账号")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--secret", default=DEFAULT_SECRET)
    parser.add_argument("--user-id", default=DEFAULT_USER_ID)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--bad-timestamp", action="store_true", help="timestamp=1，预期 401")
    parser.add_argument("--bad-sign", action="store_true", help="错误 sign，预期 401")
    args = parser.parse_args()

    timestamp = 1 if args.bad_timestamp else None
    body, _nonce = signed_body(
        secret=args.secret,
        user_id=args.user_id,
        action="login",
        timestamp=timestamp,
        bad_sign=args.bad_sign,
    )
    body["password"] = args.password

    url = f"{args.base_url.rstrip('/')}/api/login"
    print("canonical action=login")
    print("request:", json.dumps(body, ensure_ascii=False))
    status, parsed = post_json(url, body)
    print(f"HTTP {status}")
    print(json.dumps(parsed, ensure_ascii=False, indent=2) if isinstance(parsed, dict) else parsed)

    if isinstance(parsed, dict) and parsed.get("ok") is True:
        token = parsed.get("token")
        print("token:", token)
        print("login ok")
        return 0

    print("login failed")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
