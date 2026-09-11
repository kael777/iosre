#!/usr/bin/env python3
"""W18：本机两个用户的水平 IDOR 对照。

只打 127.0.0.1 / 局域网。不要对生产订单号做同样的事。

  执行 2 后端（无 ACL） →  --mode open
  执行 4 后端（有 ACL） →  --mode secure

E 必须看到 B 的数据才算越权：order-b / demo-user-002 / amount=99。
只看到 HTTP 200 不够。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _local import (
    DEFAULT_BASE_URL,
    DEFAULT_PASSWORD,
    DEFAULT_PASSWORD_2,
    DEFAULT_SECRET,
    DEFAULT_USER_ID,
    DEFAULT_USER_ID_2,
    get_json,
    post_json,
    signed_body,
)

MODES = ("open", "secure")
USER_A = DEFAULT_USER_ID
USER_B = DEFAULT_USER_ID_2
ORDER_A = "order-a"
ORDER_B = "order-b"
AMOUNT_A = 10
AMOUNT_B = 99

# open = 执行 3 修复前；secure = 执行 4 加上对象级校验后。
EXPECT_STATUS = {
    "open": {
        "A": 200,
        "B": 200,
        "C": 200,
        "D": 200,
        "E": 200,
        "F": 200,
        "G": 200,
        "H": 200,
    },
    "secure": {
        "A": 200,
        "B": 200,
        "C": 200,
        "D": 200,
        "E": 403,
        "F": 401,
        "G": 403,
        "H": 200,
    },
}


def detail_of(parsed) -> str:
    if not isinstance(parsed, dict):
        return str(parsed)
    if parsed.get("ok") is True:
        order = parsed.get("order")
        if isinstance(order, dict):
            return (
                f"order_id={order.get('order_id')} "
                f"user_id={order.get('user_id')} "
                f"amount={order.get('amount')}"
            )
        profile = parsed.get("profile")
        if isinstance(profile, dict):
            return (
                f"user_id={profile.get('user_id')} "
                f"display_name={profile.get('display_name')}"
            )
        if parsed.get("token"):
            return f"token user_id={parsed.get('user_id')}"
        return "ok"
    return str(parsed.get("error") or parsed)


def order_fields(parsed) -> tuple[str | None, object]:
    if isinstance(parsed, dict) and isinstance(parsed.get("order"), dict):
        order = parsed["order"]
        return order.get("user_id"), order.get("amount")
    return None, None


def profile_user(parsed) -> str | None:
    if isinstance(parsed, dict) and isinstance(parsed.get("profile"), dict):
        return parsed["profile"].get("user_id")
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="本机水平 IDOR 对照")
    parser.add_argument("--mode", choices=MODES, default="open")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    expect = EXPECT_STATUS[args.mode]
    secret = DEFAULT_SECRET

    print(f"target: {base}")
    print(f"mode:   {args.mode}")
    if args.mode == "open":
        print("修复前：E 必须读到 002 的 order-b / amount=99，才算水平 IDOR。")
    else:
        print("修复后：E/F/G 应 403/401/403；H 读自己的 order-a 仍 200。")
    print()

    rows: list[tuple[str, str, int, int, str, bool]] = []

    def add(code: str, title: str, status: int, parsed, extra_ok: bool = True) -> None:
        wanted = expect[code]
        ok = status == wanted and extra_ok
        rows.append((code, title, wanted, status, detail_of(parsed), ok))

    body_a, _ = signed_body(secret=secret, user_id=USER_A, action="login")
    body_a["password"] = DEFAULT_PASSWORD
    status_a, parsed_a = post_json(f"{base}/api/login", body_a)
    token_a = parsed_a.get("token") if isinstance(parsed_a, dict) else None
    add("A", "001 登录", status_a, parsed_a, extra_ok=bool(token_a))

    body_b, _ = signed_body(secret=secret, user_id=USER_B, action="login")
    body_b["password"] = DEFAULT_PASSWORD_2
    status_b, parsed_b = post_json(f"{base}/api/login", body_b)
    token_b = parsed_b.get("token") if isinstance(parsed_b, dict) else None
    add("B", "002 登录", status_b, parsed_b, extra_ok=bool(token_b))

    body_c, _ = signed_body(secret=secret, user_id=USER_A, action="order")
    body_c["order_id"] = ORDER_A
    body_c["amount"] = AMOUNT_A
    status_c, parsed_c = post_json(f"{base}/api/order", body_c)
    user_c, amount_c = order_fields(parsed_c)
    add(
        "C",
        "001 创建 order-a amount=10",
        status_c,
        parsed_c,
        extra_ok=user_c == USER_A and amount_c == AMOUNT_A,
    )

    body_d, _ = signed_body(secret=secret, user_id=USER_B, action="order")
    body_d["order_id"] = ORDER_B
    body_d["amount"] = AMOUNT_B
    status_d, parsed_d = post_json(f"{base}/api/order", body_d)
    user_d, amount_d = order_fields(parsed_d)
    add(
        "D",
        "002 创建 order-b amount=99",
        status_d,
        parsed_d,
        extra_ok=user_d == USER_B and amount_d == AMOUNT_B,
    )

    auth_a = {"Authorization": f"Bearer {token_a}"} if token_a else {}
    status_e, parsed_e = get_json(f"{base}/api/orders/{ORDER_B}", headers=auth_a or None)
    user_e, amount_e = order_fields(parsed_e)
    if args.mode == "open":
        extra_e = user_e == USER_B and amount_e == AMOUNT_B
    else:
        extra_e = True
    add("E", "token_a GET order-b", status_e, parsed_e, extra_ok=extra_e)

    status_f, parsed_f = get_json(f"{base}/api/orders/{ORDER_B}")
    add("F", "无 token GET order-b", status_f, parsed_f)

    status_g, parsed_g = get_json(f"{base}/api/profile/{USER_B}", headers=auth_a or None)
    if args.mode == "open":
        extra_g = profile_user(parsed_g) == USER_B
    else:
        extra_g = True
    add("G", "token_a GET profile/002", status_g, parsed_g, extra_ok=extra_g)

    status_h, parsed_h = get_json(f"{base}/api/orders/{ORDER_A}", headers=auth_a or None)
    user_h, amount_h = order_fields(parsed_h)
    add(
        "H",
        "token_a GET 自己的 order-a",
        status_h,
        parsed_h,
        extra_ok=user_h == USER_A and amount_h == AMOUNT_A,
    )

    print(f"{'ID':<4} {'用例':<32} {'预期':<6} {'实际':<6} {'结果':<6} 说明")
    print("-" * 100)
    all_ok = True
    for code, title, wanted, status, detail, ok in rows:
        all_ok &= ok
        mark = "OK" if ok else "FAIL"
        print(f"{code:<4} {title:<32} {wanted:<6} {status:<6} {mark:<6} {detail}")
    print("-" * 100)
    print("ALL PASS" if all_ok else "SOME FAILED")
    if args.mode == "open" and all_ok:
        print("这是水平 IDOR：A 的会话读到了 B 的订单，不是 UI 隐藏问题。")
    if args.mode == "secure" and not all_ok:
        print("若 E/F/G 仍是 200，说明还没加 ACL，或 SKIP_ACL=1，或没重启 app.py。")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
