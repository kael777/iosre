# W5 SignDemo 协议可见性

## 环境

- 日期：2026-09-10
- 设备：iPhone XR / iOS 18.5 / arm64e / Dopamine
- Mac：Mac mini 2023（Apple M2）/ macOS 26.6.2 / Xcode 26.6
- App：`com.weideshun.SignDemo`
- 后端：`https://192.168.1.8:5443`（HTTP `:5000` 回退）
- 后端路径：`/Users/weideshun/Desktop/SignDemo/backend/`
- WebSocket：`wss://192.168.1.8:5443/ws/events`
- gRPC：`127.0.0.1:5445`（独立端口，不占 5443）
- Frida：本周主线未使用
- mitmproxy：12.2.3，监听 `8080`

账号、token、订单均为虚构测试数据。私钥未写入笔记。

观察 WS / HTTP/2 时把 App 的 **Pinning 关掉**。否则失败发生在证书层，会误判成协议问题。实验结束后把 Pinning 打开，确认代理下 Health 仍失败。

## WebSocket

- URL：`wss://192.168.1.8:5443/ws/events?token=<login 返回的虚构 token>`
- App：先 **Login** 保存 token，再 **Connect WS**
- 握手：HTTP `GET /ws/events`，`Upgrade: websocket`，状态 **101**
- 帧内容（约每 5 秒）：

```json
{"ok": true, "type": "tick", "service": "SignDemo", "time": 1789028662}
```

- Pinning 当时：抓包时 **OFF**；Pinning ON + 代理时 WS 同样在证书层失败
- 无 token：服务端返回 `{"ok": false, "error": "missing token"}` 并关闭
- 实现：后端 `flask-sock` 路由 `/ws/events`；App `NSURLSessionWebSocketTask`，复用带 Pinning delegate 的 `NSURLSession`

mitmproxy 启动仍需带练习 CA：

```bash
mitmweb --listen-port 8080 \
  --set ssl_verify_upstream_trusted_ca=/Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt
```

## HTTP/1.1 vs HTTP/2

- Flask `./.venv/bin/python3 app.py` 的 HTTPS `:5443` 是 **HTTP/1.1**。HTTPS ≠ HTTP/2。
- Hypercorn 0.18 带 `--certfile` / `--keyfile` 后自动 ALPN；**没有** `--alpn-protocol` 参数。不要加 `--quic-bind`。

```bash
./.venv/bin/hypercorn app:app \
  --bind 0.0.0.0:5443 \
  --certfile certs/server.crt \
  --keyfile certs/server.key
```

```bash
curl -vk --http1.1 --cacert certs/ca.crt https://127.0.0.1:5443/api/health
curl -vk --http2 --cacert certs/ca.crt https://127.0.0.1:5443/api/health
```

- Flask 版本：HTTP/1.1 200
- Hypercorn 版本：HTTP/2（ALPN: h2）
- 多路复用：HTTP/2 是同一条 TCP 连接上并行多条流，不是「更加密」。它仍是 TCP，系统 HTTP 代理仍可能工作。
- WebSocket 只保证在 Flask `app.py` 上。对照完 HTTP/2 后改回 `./.venv/bin/python3 app.py`。

## QUIC

- TCP 5443：有进程 `LISTEN`
- UDP 5443 / 443：没有 SignDemo 在听
- 未使用 Hypercorn `--quic-bind`
- App 使用 `NSURLSession` 的 TCP HTTPS / WebSocket，未配置 HTTP/3

结论：

```text
没有 UDP
系统 Wi-Fi HTTP 代理只管 TCP
mitmproxy 不是 QUIC 代理
服务端没有 H3
抓不到不一定是 Pinning；若走 QUIC，代理根本接不住
练习降级：SIGNDEMO_HTTP3=0，不听 UDP，抓包走 TCP HTTPS / WS
```

QUIC ≠「HTTPS 抓不到」。差别在传输层是 UDP 还是 TCP。

## gRPC

- proto：`/Users/weideshun/Desktop/SignDemo/backend/proto/signdemo.proto`
- 服务：`./.venv/bin/python3 grpc_server.py`（端口 5445，同一套练习证书）
- 客户端：`./.venv/bin/python3 grpc_ping.py`，成功，`ok=true`，`service=SignDemo`
- 本周未编进 iOS App

Ping 字段编号：

| 消息 | 字段 | 编号 | wire 类型 |
|---|---|---|---|
| PingRequest | user_id | 1 | string / length-delimited |
| PingRequest | timestamp | 2 | varint |
| PingReply | ok | 1 | varint |
| PingReply | service | 2 | string / length-delimited |
| PingReply | time | 3 | varint |

序列化后是二进制，例如 `0a0d64656d6f2d757365722d303031...`。没有 `.proto` 时，抓到的 body 不像 `/api/health` 的 JSON 好读。这是 protobuf 编码，不是「加密更强」。

## 对照表

| 协议 | 传输层 | 代理可见性 | 适合的分析方式 |
|---|---|---|---|
| HTTP/1.1 | TCP | 高；解密后可见 Header 和 JSON | mitmproxy |
| HTTP/2 | TCP | 取决于代理是否支持 h2 | mitmproxy / curl --http2 |
| WebSocket | TCP（先 HTTP 升级） | 握手是 HTTP 101；之后看帧 | mitmproxy |
| QUIC / HTTP/3 | UDP | 系统 HTTP 代理通常看不见 | 先确认有无 UDP；练习中关闭 H3 再抓 |
| gRPC | 一般在 HTTP/2 上 | 二进制，需 schema | `.proto` + 测试客户端 |

## 和 W4 的关系

W4 问证书信谁。W5 问同样加密时代理能看见哪一层。mitmproxy 连练习 HTTPS 仍要带 `ca.crt`。真机不要用 `127.0.0.1`。后端继续放在工程根下的 `backend/`，不要放进 App 同步目录。

## 产物

```text
/Users/weideshun/Desktop/SignDemo/backend/app.py          （/ws/events）
/Users/weideshun/Desktop/SignDemo/SignDemo/APIClient.m     （NSURLSessionWebSocketTask）
/Users/weideshun/Desktop/SignDemo/backend/proto/signdemo.proto
/Users/weideshun/Desktop/SignDemo/backend/grpc_server.py
/Users/weideshun/Desktop/SignDemo/backend/grpc_ping.py
/Users/weideshun/Downloads/ll/notes/week-05-protocols.md
```

## 未验证项

- 未给 SignDemo 上完整 HTTP/3 栈（本周明确不做）。
- 未把 gRPC 编进 iOS。
- 未在 Hypercorn 上验证 WebSocket。
- 未对第三方 App 做协议还原。

## 下一步

进入 [`iOS逆向实施步骤/06-W6-M1综合验收-详细执行步骤.md`](../iOS逆向实施步骤/06-W6-M1综合验收-详细执行步骤.md)。不要把 W19 的越狱检测提前做完。
