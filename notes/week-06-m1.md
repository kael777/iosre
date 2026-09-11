# W6 SignDemo M1

## 环境

- 日期：2026-09-11
- 设备：iPhone XR / iOS 18.5 / arm64e / Dopamine
- Mac：Mac mini 2023（Apple M2）/ macOS 26.6.2 / Xcode 26.6
- App：`com.weideshun.SignDemo`
- 后端：`https://192.168.1.8:5443`（HTTP `:5000` 回退）
- 后端路径：`/Users/weideshun/Desktop/SignDemo/backend/`
- Frida：17.17.0（本周回归时已退出）
- mitmproxy：12.2.3，回归时代理已关

测试数据均为虚构：`demo-user-001` / `demo-password` / `order-001` / amount `10`。

## 业务链（每步结果）

无代理、Pinning 打开、反调试关闭：

| 步骤 | 结果 |
|---|---|
| Health | `GET /api/health` 200 |
| Login | `POST /api/login` 200，保存虚构 token |
| Profile | `GET /api/profile/demo-user-001` 200，`display_name=Demo User` |
| Create Test Order | `POST /api/order` 200，`status=created` |
| Connect WS | `wss://.../ws/events?token=...`，收到 `type=tick` |
| Disconnect WS | 主动断开 |

Profile 为未签名 GET，已写入流量报告。

## 防护开关影响表

| 编号 | 变化 | 结果 |
|---|---|---|
| P0 | HTTPS，Pinning OFF，无代理，无 Frida | 主流程成功，基线 |
| P1 | 只打开 Pinning，无代理 | 直连成功 |
| P2 | Pinning ON + 代理 | Health 失败，证书指纹不匹配（W4 验证，本周回归保持该行为） |
| P3 | timestamp=1 | HTTP 401，`request timestamp is outside the allowed window` |
| P4 | 同一 nonce 第二次 | HTTP 409，`nonce has already been used` |
| P5 | 错误 sign | HTTP 401，`invalid signature` |
| P6 | 反调试开，无 Frida | 文本区打印状态；业务仍成功；不 exit |
| P7 | 反调试开 + Frida | 命中 `P_TRACED` / `isatty` 时提示「检测到调试/跟踪」，进程不退出 |

三种失败不要混：Pinning 是 TLS 层；401 是签名/时间窗；409 是 nonce。

反调试：`AntiDebug`，默认关，无 `ptrace(PT_DENY_ATTACH)`，无 `exit()`。

## 离线复现

```text
/Users/weideshun/Desktop/SignDemo/scripts/reproduce/sign_login.py
/Users/weideshun/Desktop/SignDemo/scripts/reproduce/sign_order.py
```

只允许 `127.0.0.1` 或局域网 IP。canonical 与 App 相同：

```text
user_id=&timestamp=&nonce=&action=
HMAC-SHA256(local-demo-secret-v1, canonical)
```

- `sign_login.py`：HTTP 200，打印虚构 token
- `sign_order.py`：每次新 nonce，HTTP 200，`status=created`
- `--bad-timestamp`：401
- `--bad-sign`：401
- `--reuse-nonce`：第一次 200，第二次 409

## 回归

操作者已确认：

```text
退出 Frida
XR Wi-Fi 代理关闭
Pinning 打开（直连）
反调试关闭
后端 app.py 运行中
Health → Login → Profile → Order → Connect WS 可走通
```

bypass 未写入 App 默认逻辑。Pinning 开关仍可用，代理下应继续失败。

## M1 清单

- [x] HTTPS 明文可观察（Pinning OFF + 代理）。
- [x] 能识别 Pinning 并在自己的 App 上验证绕过效果（W4，本周未改掉）。
- [x] WebSocket 流程可解释。
- [x] HTTP/2、QUIC、gRPC 的差异有实操记录（`notes/week-05-protocols.md`）。
- [x] 离线脚本可以被自己的后端接受。
- [x] 报告不包含真实账号、真实 Token 或第三方数据。

## 产物

```text
/Users/weideshun/Downloads/ll/reports/SignDemo-traffic-analysis.md
/Users/weideshun/Desktop/SignDemo/scripts/reproduce/sign_login.py
/Users/weideshun/Desktop/SignDemo/scripts/reproduce/sign_order.py
/Users/weideshun/Downloads/ll/notes/week-06-m1.md
```

## 未验证项

- 未把 gRPC 编进 iOS。
- 未做越狱检测（W19）。
- 未做 secret 混淆（W11）。
- 反调试未作为默认退出。

## 下一步

进入 [`iOS逆向实施步骤/07-W7-Frida-ObjC-Runtime-详细执行步骤.md`](../iOS逆向实施步骤/07-W7-Frida-ObjC-Runtime-详细执行步骤.md)。反调试开关保持关闭。
