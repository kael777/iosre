# W18 越权与 IDOR

## 环境

- 日期：2026-09-11
- 本机：`https://127.0.0.1:5443`
- 脚本：`scripts/reproduce/idor_local_request.py`
- 报告：[`reports/local-api-idor.md`](../reports/local-api-idor.md)

## 三句话

1. **水平 IDOR**：已是 A，把 `order_id` 换成 B 的，修复前 200 且 JSON 是 `demo-user-002` / `amount=99`。
2. **UI 隐藏 ≠ ACL**：App 没有「别人的订单」按钮，GET 照样能读。
3. **对象级校验**：Bearer token 的用户必须等于资源属主；否则 403。无 token 401。自己的单仍 200。

## 对照

| 模式 | E token_a 读 order-b | F 无 token | G profile/002 | H 读自己的 order-a |
|---|---|---|---|---|
| 修复前 / SKIP_ACL=1 | 200（002 / 99） | 200 | 200 | 200 |
| 修复后（默认） | 403 | 401 | 403 | 200（001 / 10） |

## 下一步

W19 已完成：见 [`week-19-defenses.md`](week-19-defenses.md)。
