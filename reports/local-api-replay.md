# SignDemo 本机 API 重放报告（W17）

## 1. 对象和授权范围

- 日期：2026-09-11
- 后端：自己的 SignDemo Flask，`https://127.0.0.1:5443`（练习 CA）
- App：自己编写的 `com.weideshun.SignDemo`
- 虚构用户：`demo-user-001` / `demo-password`，`demo-user-002` / `demo-password-2`
- **不包含** 任何第三方、商店或生产 API
- **没有** 对真机抓到的 HTTPS 包改字段再发到非本机主机

脚本默认只允许 `127.0.0.1` / `localhost` / 私网 IP。生产请求即使只改一个字段也不能重放。

## 2. 安全模式基线（执行 1 / 执行 4）

脚本：`scripts/reproduce/replay_local_request.py --mode secure`

B 打 `/api/order`，签名按 `demo-user-001` 算完再把 `user_id` 改成 `demo-user-002`。login 改 `user_id` 会先撞上密码校验，看不清签名是否生效。

| 步骤 | 操作 | HTTP | 说明 |
|---|---|---|---|
| A | 正常签名 login | 200 | 合法请求 |
| B | 只改 `user_id`，sign 不重算 | 401 | `invalid signature` |
| C | `timestamp=1` | 401 | 时间窗外 |
| D | 原样重放 A | 409 | nonce 已用 |
| E | 去掉 `sign` | 400 | `missing fields: sign` |
| F | login 的 sign 打 `/api/order` | 401 | `invalid signature` |

执行 4 关掉全部 `SIGNDEMO_DEFECT_*` 后重跑，状态码与执行 1 相同。pytest 默认开关下 7 passed。

## 3. 缺陷开关（执行 2 / 执行 3）

默认全关。一次只开一个，必须重启 `app.py`。启动时若打开会打 `defect skip_* enabled`。

| 环境变量 | 打开后 | 关（安全） | 开（缺陷） |
|---|---|---|---|
| `SIGNDEMO_DEFECT_SKIP_SIGN=1` | 不要求、不校验 `sign` | B/E/F = 401/400/401 | B/E/F = 200 |
| `SIGNDEMO_DEFECT_SKIP_NONCE=1` | 不把 nonce 记入集合 | D = 409 | D = 200 |
| `SIGNDEMO_DEFECT_SKIP_WINDOW=1` | 不检查时间窗 | C = 401 | C = 200 |

对照（预期 HTTP，A 在四种模式下都是 200）：

```text
              A    B    C    D    E    F
secure      200  401  401  409  400  401
skip_sign   200  200  401  409  200  200
skip_nonce  200  401  401  200  400  401
skip_window 200  401  200  409  400  401
```

`SKIP_SIGN` 打开后，order 只信 body 里的 `user_id`，所以 B 能用别人的身份下单。这是演示，不是生产行为。

## 4. 本周只记录、未做成开关的现状

- **对象级权限**：`/api/order` 不看 token，只信 JSON 的 `user_id`。完整 IDOR（两个用户抢订单）留 W18。
- **频率限制**：当前没有 429。`SIGNDEMO_DEFECT_SKIP_RATELIMIT` 本周未实现。
- **不要** 把 `SIGNDEMO_SECRET` 改成空来模拟无签名；用 `SKIP_SIGN`。

## 5. 为何不能对生产 API 做同样的事

本表只证明：**自己的** 服务端关掉校验后，改包/重放会从拒绝变成 200。

对第三方或生产主机：

- 重放抓到的包、改 `user_id` / `timestamp` / 删 `sign`，即使只改一个字段，也是未授权测试
- 本机 200 不表示别人的 API 也能 200
- 脚本拒绝非私网地址，就是为了避免误打出去

## 6. 复现

```bash
cd /Users/weideshun/Desktop/SignDemo/backend
./.venv/bin/python3 app.py
./.venv/bin/python3 ../scripts/reproduce/replay_local_request.py --mode secure

# 一次只开一个，测完 unset 再开下一个
SIGNDEMO_DEFECT_SKIP_SIGN=1 ./.venv/bin/python3 app.py
./.venv/bin/python3 ../scripts/reproduce/replay_local_request.py --mode skip_sign
```
