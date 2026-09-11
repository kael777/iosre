# W17 API 重放

## 环境

- 日期：2026-09-11
- 本机：`https://127.0.0.1:5443`
- 脚本：`scripts/reproduce/replay_local_request.py`
- 报告：[`reports/local-api-replay.md`](../reports/local-api-replay.md)

## 三句话

1. **安全模式**：改 `user_id`、过期时间戳、重放 nonce、删 sign、action 与路径不一致，都应失败。
2. **缺陷开关**：一次只开一个；关=拒绝，开=同一请求变 200。测完必须 unset 并回归。
3. **范围**：只打自己的后端。生产包不能重放。IDOR 留 W18。

## 对照摘要

| 开关 | 被放行的步骤 |
|---|---|
| 全关 | 无（B–F 失败） |
| SKIP_SIGN | B 改 user_id、E 删 sign、F 错 action |
| SKIP_NONCE | D 原样重放 |
| SKIP_WINDOW | C timestamp=1 |

B 用 `/api/order` 改 `user_id`。login 改 `user_id` 在 SKIP_SIGN 下仍 401 密码错误。

## 下一步

W18 已完成：见 [`week-18-business-logic.md`](week-18-business-logic.md)。
