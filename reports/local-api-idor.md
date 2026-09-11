# SignDemo 本机水平 IDOR 报告（W18）

## 1. 对象和授权范围

- 日期：2026-09-11
- 后端：自己的 SignDemo Flask，`https://127.0.0.1:5443`
- App：自己编写的 `com.weideshun.SignDemo`
- 虚构用户：`demo-user-001` / `demo-password`，`demo-user-002` / `demo-password-2`
- **不包含** 任何第三方、商店或生产 API
- **没有** 对真实订单号、用户 ID 做探测

脚本：`scripts/reproduce/idor_local_request.py`  
只允许 `127.0.0.1` / 私网 IP。生产对象不可改 ID 重放。

## 2. 必须分清的三件事

| 容易写错 | 本周实际 |
|---|---|
| SignDemo 界面没有「别人的订单」按钮 | 那是 **UI 隐藏**，不是权限 |
| 改 `order_id` 后 HTTP 200 | 还要看 JSON 是不是 **B 的** `user_id` / `amount` |
| 200 就等于成功 | 看 `ok` 和业务字段；修复后越权应变 **403**，不是假装 200 |

HMAC 能签任意 `user_id` 是共享 secret（W17），不是本周 IDOR。本周是：已经登录成 A，只改对象 ID。

## 3. 两个用户、两笔订单

| 用户 | token 前缀 | order_id | amount |
|---|---|---|---|
| demo-user-001 | `demo-token-demo-user-001-` | order-a | 10 |
| demo-user-002 | `demo-token-demo-user-002-` | order-b | 99 |

amount 故意不同，用来证明读到的是 B 的单，不是「随便一个 200」。

## 4. 修复前（执行 3，`--mode open`）

当时 `GET /api/orders/<id>` 和 `GET /api/profile/<user_id>` **不看** token。

| 步骤 | 操作 | HTTP | 正文要点 |
|---|---|---|---|
| A/B | 001 / 002 登录 | 200 | 两枚不同 token |
| C | 001 创建 order-a | 200 | `user_id=demo-user-001` `amount=10` |
| D | 002 创建 order-b | 200 | `user_id=demo-user-002` `amount=99` |
| **E** | `Authorization: Bearer token_a` GET `/api/orders/order-b` | **200** | **`order_id=order-b user_id=demo-user-002 amount=99`** |
| F | 无 token GET order-b | 200 | 同上 |
| G | token_a GET `/api/profile/demo-user-002` | 200 | `Second Demo User` |
| H | token_a GET order-a | 200 | 自己的单 |

E 的 JSON 是 002 / 99，所以是 **水平 IDOR**：A 的会话读到了 B 的对象。  
无 token 也能读 profile/订单，说明 login 发出 token ≠ 读接口在用 token。

## 5. 修复（执行 4）

位置：`backend/app.py`

- login 把 `token → user_id` 记进 `issued_tokens`（约 218 行）
- `POST /api/order` 写入 `stored_orders`，**仍只验 HMAC**，不强制 token（避免拆掉 App / W17）
- `bearer_user_id()`：读 `Authorization: Bearer`（约 197 行）
- `GET /api/orders/<order_id>`（约 266 行）：无/无效 token → **401**；订单不存在 → **404**；`order.user_id != token 用户` → **403** `forbidden`
- `GET /api/profile/<user_id>`（约 309 行）：同样 401 / 403
- `SIGNDEMO_DEFECT_SKIP_ACL=1` 恢复执行 3 的放行，默认 **0**

## 6. 修复后（执行 4 / 执行 5，`--mode secure`）

现网重启加载新代码后：

| 步骤 | HTTP | 说明 |
|---|---|---|
| C/D 自己下单 | 200 | 不变 |
| E token_a GET order-b | **403** `forbidden` | 不能读 B |
| F 无 token GET order-b | **401** `missing or invalid token` | |
| G token_a GET profile/002 | **403** `forbidden` | |
| H token_a GET order-a | **200** | `demo-user-001` / `10` |

`SKIP_ACL=1` 时 E 回到 200，正文仍是 `demo-user-002` / `99`。测完 unset。

## 7. 回归

- pytest：13 passed（含属主 200、他人 403、无 token 401、`SKIP_ACL` 放行）
- W17 `replay_local_request.py --mode secure`：ALL PASS（签名 / 时间窗 / nonce 未拆）
- `idor_local_request.py --mode secure`：ALL PASS

## 8. 未做

- POST `/api/order` 仍信签名里的 `user_id`，创建侧未绑 token（本周打的是 **读对象**）
- 无垂直越权、无真实数据库、无频率限制
- 生产 / 第三方对象 ID 不做同样测试
