# W18 越权、IDOR 与修复验证：详细执行步骤

> 本文件是 [`iOS逆向_2026Q1完整实施计划.md`](../iOS逆向_2026Q1完整实施计划.md) 中“22. W18：越权、IDOR 和修复验证”的执行手册。  
> **只打自己的 SignDemo 后端**（`127.0.0.1` / 局域网 IP）。  
> 不要对第三方/生产 API 改 `user_id`、`order_id` 或拿别人的对象。

---

## 本周在练什么

W17 证明：**没签对就进不了接口**。W18 证明：**签对了、登录了，也不该拿到别人的对象**。

```text
两个虚构用户各拿自己的 token
→ 各自下一笔不同的订单
→ 用 A 的 token 去读 B 的订单 / profile
→ 修复前：200，而且响应里真是 B 的数据（这才叫越权）
→ 服务端按 token 做对象级校验
→ 同一请求应变 403
→ A 读自己的订单仍 200
```

当前后端 **已有**：HMAC、时间窗、nonce、login 签发 `demo-token-...`。  
当前 **没有**：token 表、订单存储、GET 订单、按属主拒绝。  
`/api/profile/<user_id>` **谁都能 GET**。App 界面只有一个 `user_id` 框，不显示别人的订单 **≠** 服务端有权限。

---

## 术语

| 术语 | 含义 |
|---|---|
| **越权** | 已认证为 A，却读到或改了 B 的数据。 |
| **IDOR** | 直接改对象 ID（`order_id` / URL 里的 `user_id`）就拿到别人的资源。 |
| **对象级权限** | 不仅要有合法 token，还要 `资源.user_id == token 对应的用户`。 |
| **水平越权** | 同角色用户互访（001 读 002）。本周只做这个。 |
| **垂直越权** | 普通用户打到管理员接口。本周不做。 |

报告必须分清：

| 容易写错 | 本周要写的 |
|---|---|
| 客户端没画「别人的订单」按钮 | 那只是 UI 隐藏，不是权限 |
| 改参数后 HTTP 200 | 必须核对 JSON 里是 **B 的** `user_id` / `amount` / `order_id` |
| 接口返回 200 就等于成功 | 看 `ok` 和业务字段，不要只看状态码 |

HMAC 能签任意 `user_id` 是 **共享 secret**（W17），不是本周 IDOR。本周是：已经是 A，只改对象 ID。

---

## 当前状态

- 后端：`/Users/weideshun/Desktop/SignDemo/backend/app.py`
- 虚构用户已在 `DEMO_USERS`：
  - `demo-user-001` / `demo-password`
  - `demo-user-002` / `demo-password-2`
- `POST /api/order`：校验 HMAC 后把 body 原样回显，**不入库**，**不看 token**
- `GET /api/profile/<user_id>`：无 Authorization
- login 的 token 只给 WebSocket 做「非空」检查
- W17 脚本 `replay_local_request.py` 必须继续绿，本周不要拆掉签名校验

---

## 本文件完成后的结果

- 内存订单表 + `GET /api/orders/<order_id>`
- token → user 映射；对象级 ACL（可用 `SIGNDEMO_DEFECT_SKIP_ACL` 对照）
- `scripts/reproduce/idor_local_request.py`
- `reports/local-api-idor.md`
- `notes/week-18-business-logic.md`

执行顺序：

```text
执行 1  两个用户登录；用现有 profile 证明无鉴权就能读别人
执行 2  订单入库 + GET（先不加 ACL）
执行 3  A 的 token 读 B 的订单，核对响应语义
执行 4  加上对象级校验，同一请求变 403
执行 5  回归 + pytest + 报告
```

---

## 执行 1：两个用户，先证明现状（不改后端）

后端和平时一样启动（不要带 W17 缺陷开关）：

```bash
cd /Users/weideshun/Desktop/SignDemo/backend
./.venv/bin/python3 app.py
```

### 1.1 各登录一次，记下 token

```bash
cd /Users/weideshun/Desktop/SignDemo
./backend/.venv/bin/python3 scripts/reproduce/sign_login.py \
  --user-id demo-user-001 --password demo-password

./backend/.venv/bin/python3 scripts/reproduce/sign_login.py \
  --user-id demo-user-002 --password demo-password-2
```

应各得 `HTTP 200` 和不同的 `token`（`demo-token-demo-user-001-...` / `demo-token-demo-user-002-...`）。

### 1.2 无 token 读别人的 profile

```bash
curl --cacert /Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt \
  https://127.0.0.1:5443/api/profile/demo-user-002
```

预期：**200**，JSON 里 `profile.user_id=demo-user-002`、`display_name=Second Demo User`。  
没带 token 也能读，说明「发出 token」≠「接口在用 token」。

### 1.3 对照 App

SignDemo 界面没有「查看用户 002」的按钮，只有一个 `user_id` 输入。把这记成：**客户端隐藏 ≠ 权限控制**。

把 HTTP 状态和 JSON 关键字段填进执行记录。不要只写 200。

### 验收标准

- [x] 两个用户各有独立 token
- [x] 无 token 的 profile 响应里能看到 002 的 `display_name`

---

## 执行 2：订单入库 + GET（先故意无 ACL）

只改自己的 `app.py`。W17 的 login/order HMAC 行为保持不变。

建议最小增量：

```text
login 成功 → 把 token 记进 tokens[token] = user_id
POST /api/order 成功 → 把订单记进 orders[order_id]
  {order_id, user_id, amount, status}
GET /api/orders/<order_id>
  没有 → 404
  有 → 200 返回该订单   ← 本步还不要校验 token / 属主
```

约定测试对象（虚构）：

| 用户 | 密码 | order_id | amount |
|---|---|---|---|
| demo-user-001 | demo-password | order-a | 10 |
| demo-user-002 | demo-password-2 | order-b | 99 |

`amount` 故意不同，后面才能证明读到的是 **B 的单**，不是「随便一个 200」。

进程内字典即可，重启后端订单会丢，对练习足够。不要接真实数据库。

`GET /api/profile/<user_id>` 本步先不动，留给执行 4 一起加校验。

pytest 仍须全绿（现有 7 个用例不依赖入库）。

### 验收标准

- [x] 001 / 002 各 POST 一笔，再 GET 自己的 `order_id` 能 200
- [x] pytest 仍通过
- [x] GET 此时 **还不** 看 Authorization

---

## 执行 3：用 A 的 token 请求 B 的对象

在执行 2 的无 ACL 后端上跑。先写 `scripts/reproduce/idor_local_request.py`（可先手跑，再收进脚本）。

只允许 `127.0.0.1` / 局域网，复用 `_local.py`。

| 步骤 | 操作 | 预期（修复前） |
|---|---|---|
| A | 001 登录 | 200，token_a |
| B | 002 登录 | 200，token_b |
| C | 001 签名创建 `order-a` amount=10 | 200，`user_id=demo-user-001` |
| D | 002 签名创建 `order-b` amount=99 | 200，`user_id=demo-user-002` |
| E | `Authorization: Bearer token_a` GET `/api/orders/order-b` | **200**，且 `user_id=demo-user-002`、`amount=99` |
| F | 无 token GET `/api/orders/order-b` | 200（本步仍无 ACL） |
| G | token_a GET `/api/profile/demo-user-002` | 200，display_name 是 002 的 |

E 必须把响应正文抄进记录。若 200 但 `user_id` 仍是 001，那就不是越权，是自己的单，不能当 IDOR。

不要对商店 App 或生产订单号做同样的事。

### 验收标准

- [x] E 的 JSON 明确是 002 的订单（id + amount 对得上）
- [x] 记录里写了「这是水平 IDOR，不是 UI 问题」

---

## 执行 4：对象级校验

同一套请求，服务端开始拒绝。

规则（默认开启，即安全模式）：

```text
从 Authorization: Bearer <token> 取出 token
token 不在表里 → 401
GET /api/orders/<id>
  订单不存在 → 404
  order.user_id != token 的 user → 403   （不要回 200）
  匹配 → 200
GET /api/profile/<user_id>
  同样：无 token 401；user_id 不是自己 → 403
```

可选对照开关（默认 **关** = 校验开启）：

```text
SIGNDEMO_DEFECT_SKIP_ACL=0    # 1=恢复执行 3 的放行，仅本机演示
```

打开时打日志：`defect skip_acl enabled`。不要默认开。

POST `/api/order`：本周 **不要** 改成必须带 token（否则 App 下单和 W17 脚本会一起坏）。属主仍以签名过的 `user_id` 为准。本周打的是 **读对象** 的 IDOR。

执行 3 的表，修复后：

| 步骤 | 预期（修复后） |
|---|---|
| C / D 自己下单 | 仍 200 |
| E token_a 读 order-b | **403** |
| F 无 token 读 order-b | **401** |
| G token_a 读 profile/002 | **403** |
| 对照：token_a 读 order-a | 仍 **200**，且是 001 的数据 |
| 对照：token_b 读 order-b | 仍 **200** |

App 可以不改。脚本带 `Authorization` 头即可。

### 验收标准

- [x] E/F/G 从放行变成 401/403
- [x] A 读自己的订单仍 200，正文仍是自己的
- [x] `SKIP_ACL=1` 时 E 能回到 200（测完立刻 unset）

---

## 执行 5：回归、脚本、报告

```bash
unset SIGNDEMO_DEFECT_SKIP_ACL
# 重启 app.py
cd /Users/weideshun/Desktop/SignDemo/backend
./.venv/bin/python3 -m pytest -q
./.venv/bin/python3 ../scripts/reproduce/replay_local_request.py --mode secure
./.venv/bin/python3 ../scripts/reproduce/idor_local_request.py --mode secure
```

W17 A–F 必须仍 ALL PASS。IDOR 脚本在 secure 下 E/F/G 失败（401/403），自己的单成功。

产物：

```text
scripts/reproduce/idor_local_request.py
reports/local-api-idor.md
notes/week-18-business-logic.md
```

报告必须有：

- 两个用户、两笔不同订单
- 修复前 E 的 JSON（证明读到 B）
- 修复后状态码 + 服务端校验代码位置
- 写明：UI 隐藏 ≠ ACL；200 ≠ 业务成功
- **只含本机后端**；生产对象 ID 不可探测

### 验收标准

- [x] 能构造两个独立测试用户
- [x] 能证明修复前后的差异
- [x] 报告含代码位置和回归结果
- [x] W17 重放脚本未回归失败

---

## 不要做的事

- 不要对真实 App / 生产订单、用户 ID 做 IDOR 探测。
- 不要本周做管理员垂直越权。
- 不要把 ACL 开关默认打开缺陷。
- 不要为了演示越权而关掉 HMAC（那是 W17）。
- 不要把 POST `/api/order` 改成必须 token，除非同步改 App 和 W17 脚本。
- 不要接外部数据库、不要发真实支付。

---

## 执行记录

### 执行 1：两个用户 / profile 现状

```text
日期：2026-09-11
token_001：demo-token-demo-user-001-…（与 002 不同）
token_002：demo-token-demo-user-002-…
GET /api/profile/demo-user-002（无 token）：200
  user_id=demo-user-002
  display_name=Second Demo User
结果：完成。发出 token ≠ 接口在用 token。App 无「查看 002」按钮。
```

### 执行 2：入库 + GET

```text
日期：2026-09-11
GET /api/orders/order-a：200 user_id=demo-user-001 amount=10
GET /api/orders/order-b：200 user_id=demo-user-002 amount=99
GET /api/orders/does-not-exist：404
pytest：9 passed
结果：完成。GET 不看 Authorization。操作者确认符合预期。
```

### 执行 3：修复前越权

```text
日期：2026-09-11
脚本：scripts/reproduce/idor_local_request.py --mode open
A/B 登录 200；C order-a 001/10；D order-b 002/99
E token_a GET order-b：200 order_id=order-b user_id=demo-user-002 amount=99
F 无 token GET order-b：200 同上
G token_a GET profile/002：200 display_name=Second Demo User
H token_a GET order-a：200 自己的单
结果：完成 ALL PASS。水平 IDOR，不是 UI 问题。
```

### 执行 4：加上 ACL

```text
日期：2026-09-11
E token_a GET order-b：403 forbidden
F 无 token GET order-b：401 missing or invalid token
G token_a GET profile/002：403 forbidden
H token_a GET order-a：200 demo-user-001 amount=10
SKIP_ACL=1 时 E：200（002 / 99），测完 unset
结果：完成。操作者确认符合预期。
```

### 执行 5：文档

```text
脚本：scripts/reproduce/idor_local_request.py
报告：reports/local-api-idor.md
笔记：notes/week-18-business-logic.md
pytest：13 passed
W17 replay --mode secure：ALL PASS
idor --mode secure：ALL PASS（重启加载 ACL 后）
结果：完成。只含本机后端。
```
