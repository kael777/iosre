#!/usr/bin/env python3
"""M2 handoff: XOR-restore SignDemo secret, HMAC-SHA256, talk to local backend only.

Usage:
  python3 signature_v2.py
  python3 signature_v2.py --action order
  python3 signature_v2.py --bad-timestamp
  python3 signature_v2.py --reuse-nonce
"""

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
    make_signature,
    post_json,
    signed_body,
)

XOR_KEY = 0x5A
PART_A = bytes.fromhex("3635393b36773e3f3735")
PART_B = bytes.fromhex("77293f39283f2e772c6b")

SAMPLE_LOGIN_TS = 1789104979
SAMPLE_LOGIN_NONCE = "6326a68ba2771970"
SAMPLE_LOGIN_SIGN = "fbbb5d8ea2f97df8863d7ee299e03e6943404de7b192afd92e9738a3de9a42fd"


def deobfuscate_secret() -> str:
    secret = bytes(byte ^ XOR_KEY for byte in PART_A + PART_B).decode("utf-8")
    if secret != DEFAULT_SECRET:
        raise SystemExit(f"还原结果不是预期明文：{secret!r}")
    return secret


def send(action: str, secret: str, args) -> tuple[int, dict | str, str]:
    timestamp = 1 if args.bad_timestamp else None
    body, nonce = signed_body(
        secret=secret,
        user_id=args.user_id,
        action=action,
        timestamp=timestamp,
        bad_sign=args.bad_sign,
    )
    if action == "login":
        body["password"] = args.password
        path = "/api/login"
    else:
        body["order_id"] = args.order_id
        body["amount"] = args.amount
        path = "/api/order"
    url = f"{args.base_url.rstrip('/')}{path}"
    print("canonical action=%s" % action)
    print("request:", json.dumps(body, ensure_ascii=False))
    status, parsed = post_json(url, body)
    print(f"HTTP {status}")
    print(json.dumps(parsed, ensure_ascii=False, indent=2) if isinstance(parsed, dict) else parsed)
    return status, parsed, nonce


def main() -> int:
    parser = argparse.ArgumentParser(description="M2：还原 secret 并复现 login/order")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--user-id", default=DEFAULT_USER_ID)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--action", choices=("login", "order"), default="login")
    parser.add_argument("--order-id", default="order-001")
    parser.add_argument("--amount", type=float, default=10)
    parser.add_argument("--bad-timestamp", action="store_true")
    parser.add_argument("--bad-sign", action="store_true")
    parser.add_argument("--reuse-nonce", action="store_true")
    parser.add_argument(
        "--verify-sample",
        action="store_true",
        help="核对执行 2 的 login 样本，不发网络请求",
    )
    args = parser.parse_args()

    secret = deobfuscate_secret()
    print("restored secret:", secret)

    if args.verify_sample:
        sign = make_signature(
            secret=secret,
            user_id=args.user_id,
            timestamp=SAMPLE_LOGIN_TS,
            nonce=SAMPLE_LOGIN_NONCE,
            action="login",
        )
        print("sign:    ", sign)
        print("expected:", SAMPLE_LOGIN_SIGN)
        if sign != SAMPLE_LOGIN_SIGN:
            print("mismatch")
            return 1
        print("matches W12 sample")
        return 0

    action = "order" if args.reuse_nonce else args.action
    status, parsed, nonce = send(action, secret, args)

    if args.reuse_nonce:
        print("--- reuse same nonce ---")
        body, _ = signed_body(
            secret=secret,
            user_id=args.user_id,
            action="order",
            nonce=nonce,
        )
        body["order_id"] = args.order_id
        body["amount"] = args.amount
        url = f"{args.base_url.rstrip('/')}/api/order"
        status2, parsed2 = post_json(url, body)
        print(f"HTTP {status2}")
        print(json.dumps(parsed2, ensure_ascii=False, indent=2) if isinstance(parsed2, dict) else parsed2)
        first_ok = isinstance(parsed, dict) and parsed.get("ok") is True
        replay_rejected = not (isinstance(parsed2, dict) and parsed2.get("ok") is True)
        if first_ok and replay_rejected:
            print("order ok; replay rejected")
            return 0
        print("reuse-nonce check failed")
        return 1

    if args.bad_timestamp or args.bad_sign:
        ok = not (isinstance(parsed, dict) and parsed.get("ok") is True)
        print("rejected as expected" if ok else "should have been rejected")
        return 0 if ok else 1

    if isinstance(parsed, dict) and parsed.get("ok") is True:
        print("%s ok" % action)
        return 0
    print("%s failed" % action)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
