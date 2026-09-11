# SignDemo 本地后端

这是学习计划第三阶段使用的本地 Flask 后端，只服务于自己的 SignDemo App。

## 1. 创建或启用虚拟环境

```bash
cd /Users/weideshun/Desktop/SignDemo/backend
source .venv/bin/activate
python -m pip install -r requirements.txt
```

如果 `.venv` 还不存在：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

## 2. 启动服务

推荐使用：

```bash
source .venv/bin/activate
python app.py
```

证书齐全时会同时监听：

```text
http://0.0.0.0:5000
https://0.0.0.0:5443
```

缺少 `certs/server.crt` 时只启动 HTTP。只要 HTTP 可以：

```bash
SIGNDEMO_TLS=0 ./.venv/bin/python3 app.py
```

临时用 HTTP/2（会占用 `:5443`，先停掉 `app.py`）：

```bash
./.venv/bin/hypercorn app:app \
  --bind 0.0.0.0:5443 \
  --certfile certs/server.crt \
  --keyfile certs/server.key
```

带证书时 Hypercorn 会自动协商 HTTP/2，不要加 `--alpn-protocol`（这版没有这个参数），也不要加 `--quic-bind`。

gRPC 是单独端口 `:5445`，不占用 Flask 的 `:5443`：

```bash
./.venv/bin/python3 grpc_server.py
```

另开终端：

```bash
./.venv/bin/python3 grpc_ping.py
```

`.proto` 在 `proto/signdemo.proto`。`user_id` 字段编号是 1，`timestamp` 是 2。本周不必编进 iOS App。

对照完再改回 `./.venv/bin/python3 app.py`，WebSocket 只在 Flask 这条路径上。

Mac 本机访问：

```bash
curl http://127.0.0.1:5000/api/health
curl -vk --cacert certs/ca.crt https://127.0.0.1:5443/api/health
```

iPhone 访问必须使用 Mac 的局域网 IP，例如：

```text
http://192.168.1.8:5000
https://192.168.1.8:5443
```

查看 Mac 当前局域网 IP：

```bash
ipconfig getifaddr en1 || ipconfig getifaddr en0
```

如果当前网络不是 `en0`/`en1`，使用实际联网接口的 IP。真机不要填 `127.0.0.1`。

登录后的 WebSocket：

```text
ws://192.168.1.8:5000/ws/events?token=<login返回的虚构token>
wss://192.168.1.8:5443/ws/events?token=<login返回的虚构token>
```

服务端每 5 秒推送一条 `{"ok": true, "type": "tick", "service": "SignDemo", "time": ...}`。缺少 token 会立即关闭。

本机可用：

```bash
python - <<'PY'
import asyncio, pathlib, ssl
import websockets

ca = pathlib.Path("certs/ca.crt")
ctx = ssl.create_default_context(cafile=str(ca))
url = "wss://127.0.0.1:5443/ws/events?token=demo-token-local"

async def main():
    async with websockets.connect(url, ssl=ctx) as ws:
        for _ in range(3):
            print(await ws.recv())

asyncio.run(main())
PY
```

## 3. 接口

### 健康检查

```bash
curl http://127.0.0.1:5000/api/health
```

### 登录

签名的 canonical 字符串固定为：

```text
user_id=<user_id>&timestamp=<timestamp>&nonce=<nonce>&action=login
```

签名算法：

```text
HMAC-SHA256(secret, canonical)
```

默认 secret：

```text
local-demo-secret-v1
```

请求示例：

```json
{
  "user_id": "demo-user-001",
  "password": "demo-password",
  "timestamp": 1730000000,
  "nonce": "unique-login-nonce-001",
  "sign": "replace-with-lowercase-hex-hmac"
}
```

### 创建测试订单

canonical 中的 action 改为 `order`：

```text
user_id=<user_id>&timestamp=<timestamp>&nonce=<nonce>&action=order
```

请求示例：

```json
{
  "user_id": "demo-user-001",
  "timestamp": 1730000000,
  "nonce": "unique-order-nonce-001",
  "sign": "replace-with-lowercase-hex-hmac",
  "order_id": "order-001",
  "amount": 10
}
```

## 4. 本地测试

```bash
source .venv/bin/activate
pytest -q
```

测试覆盖：

- health 返回 200。
- 正确签名可以登录。
- 修改字段但不修改签名会失败。
- 过期 timestamp 会失败。
- 同一 nonce 只能使用一次。
- 正确签名可以创建订单。
- 非法订单金额会失败。

## 5. 使用 Python 发送签名请求

启动后端后，另开一个终端执行：

```bash
source .venv/bin/activate
python scripts/sign_local_request.py login
python scripts/sign_local_request.py order
```

真机访问 Mac 时，把地址改为 Mac 的局域网 IP：

```bash
python scripts/sign_local_request.py login \
  --base-url http://192.168.1.20:5000
```

脚本每次自动生成新的 `timestamp`、`nonce` 和 HMAC-SHA256 `sign`。

## 6. 环境变量

默认值已经适合本地练习，也可以临时覆盖：

```bash
export SIGNDEMO_SECRET='local-demo-secret-v1'
export SIGNDEMO_HOST='0.0.0.0'
export SIGNDEMO_PORT='5000'
export SIGNDEMO_HTTPS_PORT='5443'
export SIGNDEMO_TLS='1'
export SIGNDEMO_TIME_WINDOW='300'
python app.py
```

第一阶段的 nonce 存储在进程内存中，重启服务后会清空。这是刻意保留的学习点，后面再改成持久化存储。

## 7. 注意事项

- 只使用虚构账号和虚构订单。
- 不要把真实密码、Token 或第三方请求发给这个服务。
- W4 起同时提供 HTTP 和 HTTPS；练习证书私钥只放在 `backend/certs/`，不要打进 App。
- 不要把服务暴露到公网。
