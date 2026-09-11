#!/usr/bin/env python3
"""Reproduce W11 obfuscated SignDemo secret, then HMAC like the App.

Secret is stored as two XOR 0x5A parts (see SecretStore.m).
HMAC-SHA256 and canonical are unchanged. Local backend only.
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

FRIDA_TIMESTAMP = 1789103090
FRIDA_NONCE = "c07afcbfdb7942af"
FRIDA_SIGN = "ed50341d62bc8783a89ffc0503dcec23faef5de0dd8deb609d459e4a4ce116b3"


def deobfuscate_secret() -> str:
    plain = bytes(byte ^ XOR_KEY for byte in PART_A + PART_B)
    secret = plain.decode("utf-8")
    if secret != DEFAULT_SECRET:
        raise SystemExit(f"还原结果不是预期明文：{secret!r}")
    return secret


def main() -> int:
    parser = argparse.ArgumentParser(description="按 App XOR 规则还原 secret 并复现 login")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--user-id", default=DEFAULT_USER_ID)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument(
        "--verify-frida",
        action="store_true",
        help="用执行 4 抓到的 timestamp/nonce 核对 sign，不发网络请求",
    )
    args = parser.parse_args()

    secret = deobfuscate_secret()
    print("XOR key: 0x%02x" % XOR_KEY)
    print("part A xor: %s" % PART_A.hex())
    print("part B xor: %s" % PART_B.hex())
    print("restored secret:", secret)

    if args.verify_frida:
        sign = make_signature(
            secret=secret,
            user_id=args.user_id,
            timestamp=FRIDA_TIMESTAMP,
            nonce=FRIDA_NONCE,
            action="login",
        )
        canonical = (
            f"user_id={args.user_id}"
            f"&timestamp={FRIDA_TIMESTAMP}"
            f"&nonce={FRIDA_NONCE}"
            f"&action=login"
        )
        print("canonical:", canonical)
        print("sign:     ", sign)
        print("expected: ", FRIDA_SIGN)
        if sign != FRIDA_SIGN:
            print("mismatch")
            return 1
        print("matches Frida capture")
        return 0

    body, _nonce = signed_body(
        secret=secret,
        user_id=args.user_id,
        action="login",
    )
    body["password"] = args.password
    url = f"{args.base_url.rstrip('/')}/api/login"
    print("request:", json.dumps(body, ensure_ascii=False))
    status, parsed = post_json(url, body)
    print(f"HTTP {status}")
    print(json.dumps(parsed, ensure_ascii=False, indent=2) if isinstance(parsed, dict) else parsed)
    if isinstance(parsed, dict) and parsed.get("ok") is True:
        print("login ok")
        return 0
    print("login failed")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
