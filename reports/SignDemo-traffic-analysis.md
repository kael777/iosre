# SignDemo 流量分析

- 日期：2026-09-10
- App：`com.weideshun.SignDemo`
- 后端：`https://192.168.1.8:5443`（HTTP `:5000` 回退）
- 观察条件：证书 Pinning **关闭** + mitmproxy `8080`，上游带练习 CA
- 数据：下列账号、密码、token 均为虚构测试值，不是真实凭据

```text
user_id:  demo-user-001
password: demo-password
order_id: order-001
amount:   10
token:    demo-token-<user_id>-<16 hex>（登录成功后由后端签发）
```

mitmproxy：

```bash
mitmweb --listen-port 8080 \
  --set ssl_verify_upstream_trusted_ca=/Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt
```

Pinning 打开且走代理时，TLS 在 `PinningURLSessionDelegate` 失败，下面各接口都看不到业务明文。这是证书层，不是签名层。

---

## 共用签名规则

仅 **login** 和 **order** 使用。health、profile、WS 不签名。

```text
canonical =
    "user_id=" + user_id
    + "&timestamp=" + timestamp
    + "&nonce=" + nonce
    + "&action=" + action

sign = HMAC-SHA256(local-demo-secret-v1, canonical)
```

- 输出为小写十六进制。
- `action`：login 用 `login`，order 用 `order`。
- `timestamp`：Unix 秒，允许与服务器相差 300 秒。
- `nonce`：进程内只能成功使用一次，重复返回 409。重启后端会清空。
- `password` / `order_id` / `amount` **不进入** canonical。

---

## GET /api/health

```text
接口：健康检查
请求方式：GET
路径：/api/health
认证方式：无
必填字段：无
字段含义：无请求体
签名输入：无
响应结构：
  {
    "ok": true,
    "service": "SignDemo",
    "time": 1730000000
  }
失败条件：后端未启动或 TLS/Pinning 失败时客户端报错；接口本身无业务失败码
是否签名：否
Pinning 是否影响：是。Pinning ON + 代理时请求在证书层被取消
```

用途：确认 App 能打到本机后端。

---

## POST /api/login

```text
接口：登录
请求方式：POST
路径：/api/login
Content-Type：application/json
认证方式：HMAC-SHA256 请求签名 + 虚构密码
必填字段：user_id, timestamp, nonce, sign, password
字段含义：
  user_id    测试用户，如 demo-user-001
  timestamp  Unix 秒
  nonce      一次性随机串
  sign       HMAC 十六进制
  password   虚构密码，如 demo-password
签名输入：
  user_id=&timestamp=&nonce=&action=login
响应结构（成功 200）：
  {
    "ok": true,
    "user_id": "demo-user-001",
    "display_name": "Demo User",
    "token": "demo-token-demo-user-001-<16 hex>"
  }
失败条件：
  400  缺字段 / JSON 不是对象 / timestamp 非整数
  401  timestamp 超出 300 秒
  401  sign 不正确
  401  user_id 或 password 不是测试账号
  409  nonce 已使用
是否签名：是
Pinning 是否影响：是。证书失败发生在签名校验之前
```

token 仅用于后续 WebSocket 查询参数，当前 HTTP 接口不校验 Authorization。

---

## GET /api/profile/<user_id>

```text
接口：查询资料
请求方式：GET
路径：/api/profile/<user_id>
认证方式：无（路径上的 user_id）
必填字段：路径参数 user_id
字段含义：
  user_id  必须是已配置的测试用户
签名输入：无
响应结构（成功 200）：
  {
    "ok": true,
    "profile": {
      "user_id": "demo-user-001",
      "display_name": "Demo User"
    }
  }
失败条件：
  404  未知 user_id（error: demo user not found）
是否签名：否
Pinning 是否影响：是
```

这是未签名 GET。分析时要单独标出来，不要和 login/order 混成「所有接口都签名」。

---

## POST /api/order

```text
接口：创建测试订单
请求方式：POST
路径：/api/order
Content-Type：application/json
认证方式：HMAC-SHA256 请求签名（不校验 login token）
必填字段：user_id, timestamp, nonce, sign, order_id, amount
字段含义：
  user_id    测试用户
  timestamp  Unix 秒
  nonce      一次性随机串
  sign       HMAC 十六进制
  order_id   如 order-001
  amount     正数，如 10
签名输入：
  user_id=&timestamp=&nonce=&action=order
响应结构（成功 200）：
  {
    "ok": true,
    "order": {
      "order_id": "order-001",
      "user_id": "demo-user-001",
      "amount": 10,
      "status": "created"
    }
  }
失败条件：
  400  缺签名字段 / order_id 空 / amount 不是数字或 <= 0
  401  timestamp 窗口 / 错误 sign
  409  重复 nonce
是否签名：是
Pinning 是否影响：是
```

`order_id` 和 `amount` 不进 canonical。改金额不会让 sign 变掉，这是第一阶段刻意保留的学习点。

---

## WS /ws/events

```text
接口：测试事件推送
请求方式：WebSocket（先 HTTP 升级）
路径：/ws/events?token=<login 返回的虚构 token>
认证方式：查询参数 token 非空即可；第一阶段不校验 token 是否刚签发
必填字段：token
字段含义：
  token  登录响应里的 demo-token-...
签名输入：无
握手：
  GET /ws/events?token=...
  Upgrade: websocket
  成功状态 101
响应结构（连接后约每 5 秒一帧）：
  {
    "ok": true,
    "type": "tick",
    "service": "SignDemo",
    "time": 1730000000
  }
失败条件：
  缺少 token：先发 {"ok": false, "error": "missing token"} 再断开
  Pinning ON + 代理：升级前 TLS 失败，看不到 101
  后端未开 Flask app.py：连不上（Hypercorn 对照 HTTP/2 时 WS 不保证可用）
是否签名：否
Pinning 是否影响：是
```

App 流程：Login 保存 token → Connect WS。抓包时 Pinning 必须关掉。

---

## 对照

| 接口 | 签名 | Token | 代理可见（Pinning OFF） |
|---|---|---|---|
| GET /api/health | 否 | 否 | JSON |
| POST /api/login | 是，action=login | 响应里签发 | JSON，含虚构 token |
| GET /api/profile/&lt;user_id&gt; | 否 | 否 | JSON |
| POST /api/order | 是，action=order | 否 | JSON |
| WS /ws/events | 否 | 查询参数，非空即可 | 101 + tick 帧 |

三种失败不要混：

| 现象 | 层 |
|---|---|
| Pinning 失败：证书指纹不匹配 | TLS |
| 401 invalid signature / timestamp window | 应用签名 |
| 409 nonce has already been used | 防重放 |
| mitmproxy `unable to get local issuer certificate` | 代理上游不信任练习 CA |

---

## 未写入本报告的内容

- `ca.key` / `server.key`
- 真实账号或第三方 App 流量
- gRPC `:5445`（W5 笔记，不走 App 主流程）
