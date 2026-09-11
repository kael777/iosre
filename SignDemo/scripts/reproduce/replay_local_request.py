#!/usr/bin/env python3
"""W17：本机后端 A–F 改包/重放，按缺陷开关打对照表。

对照表（预期 HTTP）：

              A    B    C    D    E    F
secure      200  401  401  409  400  401
skip_sign   200  200  401  409  200  200   B 改 user_id / E 删 sign / F action
skip_nonce  200  401  401  200  400  401   D 原样重放
skip_window 200  401  200  409  400  401   C timestamp=1

B 固定打 /api/order 再改 user_id（sign 不重算）。
login 改 user_id 在 SKIP_SIGN 下仍会 401 credentials，看不出「签名被关掉」。

先按开关启动后端，再选同一 --mode：

  SIGNDEMO_DEFECT_SKIP_SIGN=1   python app.py   →  --mode skip_sign
  SIGNDEMO_DEFECT_SKIP_NONCE=1  python app.py   →  --mode skip_nonce
  SIGNDEMO_DEFECT_SKIP_WINDOW=1 python app.py   →  --mode skip_window
  （全关）                                         →  --mode secure
"""

from __future__ import annotations

import argparse
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

MODES = ("secure", "skip_sign", "skip_nonce", "skip_window")
CASE_IDS = ("A", "B", "C", "D", "E", "F")

# 关 = 安全模式。开 = 只打开对应那一列缺陷后，同一用例应变的状态码。
SECURE_EXPECT = {
    "A": 200,
    "B": 401,
    "C": 401,
    "D": 409,
    "E": 400,
    "F": 401,
}
MODE_OVERRIDES = {
    "secure": {},
    "skip_sign": {"B": 200, "E": 200, "F": 200},
    "skip_nonce": {"D": 200},
    "skip_window": {"C": 200},
}
MODE_NOTE = {
    "secure": "全部缺陷关闭",
    "skip_sign": "SKIP_SIGN：B/E/F 应从拒绝变成 200",
    "skip_nonce": "SKIP_NONCE：D 重放应从 409 变成 200",
    "skip_window": "SKIP_WINDOW：C timestamp=1 应从 401 变成 200",
}


def expected_for(mode: str) -> dict[str, int]:
    table = dict(SECURE_EXPECT)
    table.update(MODE_OVERRIDES[mode])
    return table


def err_of(parsed) -> str:
    if isinstance(parsed, dict):
        return str(parsed.get("error") or parsed.get("ok"))
    return str(parsed)


def print_expect_matrix() -> None:
    print("开关对照表（预期 HTTP）")
    print(f"{'mode':<12} " + " ".join(f"{cid:>5}" for cid in CASE_IDS))
    for mode in MODES:
        expect = expected_for(mode)
        cells = " ".join(f"{expect[cid]:>5}" for cid in CASE_IDS)
        print(f"{mode:<12} {cells}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description="本机 A–F 开关对照表")
    parser.add_argument("--mode", choices=MODES, default="secure")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument(
        "--table-only",
        action="store_true",
        help="只打印预期对照表，不发请求",
    )
    args = parser.parse_args()

    print_expect_matrix()
    if args.table_only:
        return 0

    base = args.base_url.rstrip("/")
    login_url = f"{base}/api/login"
    order_url = f"{base}/api/order"
    secret = DEFAULT_SECRET
    expect = expected_for(args.mode)

    print(f"target: {base}")
    print(f"mode:   {args.mode}  ({MODE_NOTE[args.mode]})")
    print("一次只开一个缺陷开关，且必须与 --mode 一致。")
    print()

    rows: list[tuple[str, str, int, int, int, str]] = []

    def add(code: str, title: str, url: str, body: dict) -> None:
        status, parsed = post_json(url, body)
        rows.append(
            (code, title, SECURE_EXPECT[code], expect[code], status, err_of(parsed))
        )

    body_a, _ = signed_body(secret=secret, user_id=DEFAULT_USER_ID, action="login")
    body_a["password"] = DEFAULT_PASSWORD
    add("A", "正常 login", login_url, body_a)

    body_b, _ = signed_body(secret=secret, user_id=DEFAULT_USER_ID, action="order")
    body_b["user_id"] = "demo-user-002"
    body_b["order_id"] = "order-001"
    body_b["amount"] = 10
    add("B", "只改 user_id（order，sign 不重算）", order_url, body_b)

    body_c, _ = signed_body(
        secret=secret, user_id=DEFAULT_USER_ID, action="login", timestamp=1
    )
    body_c["password"] = DEFAULT_PASSWORD
    add("C", "timestamp=1", login_url, body_c)

    add("D", "原样重放 A", login_url, body_a)

    body_e, _ = signed_body(secret=secret, user_id=DEFAULT_USER_ID, action="login")
    body_e["password"] = DEFAULT_PASSWORD
    del body_e["sign"]
    add("E", "去掉 sign", login_url, body_e)

    body_f, _ = signed_body(secret=secret, user_id=DEFAULT_USER_ID, action="login")
    body_f["password"] = DEFAULT_PASSWORD
    body_f["order_id"] = "order-001"
    body_f["amount"] = 10
    add("F", "login 签名打 /api/order", order_url, body_f)

    print(
        f"{'ID':<4} {'用例':<38} {'关':<6} {'开':<6} {'实际':<6} {'结果':<6} 说明"
    )
    print("-" * 98)
    all_ok = True
    for code, title, closed, opened, status, detail in rows:
        ok = status == opened
        all_ok &= ok
        mark = "OK" if ok else "FAIL"
        flipped = "  关→开" if closed != opened else ""
        print(
            f"{code:<4} {title:<38} {closed:<6} {opened:<6} {status:<6} {mark:<6} {detail}{flipped}"
        )

    print("-" * 98)
    print("ALL PASS" if all_ok else "SOME FAILED")
    if args.mode != "secure" and not all_ok:
        print("若实际仍是「关」那一列，说明后端没带对应 SIGNDEMO_DEFECT_* 或没重启。")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
