# W4 TLS Pinning：详细执行步骤

> 本文件是 [`iOS逆向_2026完整实施计划.md`](../iOS逆向_2026完整实施计划.md) 中“8. W4：TLS Pinning 原理和自建 App 绕过”的执行手册。  
> 当前环境：Mac mini 2023（Apple M2、macOS 26.6.2、Xcode 26.6）+ iPhone XR（A12、arm64e、iOS 18.5）。  
> 当前路线：Dopamine 越狱 + Frida 17.17 + 自建 SignDemo + 自建本地后端。  
> 操作范围：自己的 XR、自己编写的 SignDemo/后端。不要对第三方 App 做 Pinning 绕过。

---

## App Pinning 是什么

Pinning（证书固定 / TLS Pinning）是 **App 自己再做一次证书检查**，不只相信 iOS 系统信任库。

普通 HTTPS 只问系统：

```text
对方证书是不是某张被系统（或用户）信任的 CA 签出来的？
主机名 / IP 和证书 SAN 是否匹配？
```

只要答案是「是」，请求就通过。所以：

- 你在 XR 上信任了 **SignDemo Local CA**，无代理时 App 能访问 `https://192.168.1.8:5443`。
- 你在 XR 上信任了 **mitmproxy CA**，无 Pinning 时代理可以冒充后端，mitmweb 就能看到明文。

系统信任的是「一群 CA」，不是「这一台后端的这一张证书」。mitmproxy 正是利用这一点：它用自己被你信任的 CA，现场签发一张看起来像 `192.168.1.8` 的证书。对系统来说这是合法证书。

**App Pinning 额外规定：对端必须是我预先记住的那张证书（或公钥）。** 常见比法：

| 比什么 | 含义 |
|---|---|
| 证书 SHA-256（本周用这个） | 整张服务器证书的指纹必须和 App 里写死的值一致 |
| 公钥 Pinning | 证书可以换，公钥不能换 |
| 内置 CA Pinning | 只接受自己的那一张 CA，不接受系统里其它 CA |

mitmproxy 再怎么被系统信任，它拿出来的证书指纹也不是 `backend/certs/server.crt` 的指纹，Pinning 就会拒绝。这就是 W4 要亲眼看到的现象。

本周实验里有三层，不要混：

```text
1. 系统 CA 信任
   XR 是否信任 SignDemo Local CA、是否信任 mitmproxy CA。
   位置：设置 → 证书信任设置。

2. 代理自己的上游 TLS
   mitmproxy 去连 https://192.168.1.8:5443 时，也要能验证练习 CA。
   报错 “unable to get local issuer certificate” 出在这一层，
   不是 App Pinning。处理：启动 mitmweb 时带上练习 CA，或 --ssl-insecure。

3. App Pinning
   SignDemo 代码里比较服务器证书指纹。
   位置：NSURLSessionDelegate 的 didReceiveChallenge。
   执行 4 才打开。现在还没写，所以还没有 Pinning。
```

和 Pinning **不是** 一回事的东西：

- **ATS**（`NSAllowsArbitraryLoads`）：系统拦不拦明文 HTTP。关掉 ATS 不等于关掉 Pinning。
- **用户点「信任证书」**：只影响系统信任库。
- **`--ssl-insecure`**：只让 mitmproxy 不检查上游，不管 App。
- **全局 SSL Kill Switch**：改系统 SSL，不是本周主线。

对照表（记在脑子里，执行 3 / 4 会逐行填）：

| 状态 | 系统信任 | App Pinning | 预期 |
|---|---|---|---|
| 无代理 | 信任练习 CA | 关 | 成功，mitmweb 无明文 |
| 有代理 | 也信任 mitmproxy CA | 关 | 成功，mitmweb 有明文 |
| 有代理 | 同上 | 开 | 失败，mitmweb 看不到业务 JSON |

一句话：**系统信任回答「这张证书像不像合法证书」；Pinning 回答「这张证书是不是我指定的那一张」。**

本周只在 `com.weideshun.SignDemo` 上加开关、观察和一次绕过实验。不要对第三方 App 做 Pinning 绕过。

---

## 当前状态

截至 2026-09-10，[`00.2-当前未完成-详细执行步骤.md`](00.2-当前未完成-详细执行步骤.md) 已完成。

- SignDemo 已在 XR 运行，Bundle Identifier：`com.weideshun.SignDemo`。
- 后端目前是 **HTTP**，默认地址：`http://192.168.1.8:5000`。
- 工程路径：`/Users/weideshun/Desktop/SignDemo/`。
- 后端路径：`/Users/weideshun/Desktop/SignDemo/backend/`（不要再放进 `SignDemo/SignDemo/`，否则 Xcode 会把 `.venv` 打进 App）。
- App 网络类：`APIClient`，当前使用无 delegate 的 `NSURLSession`。
- `Info.plist` 仍有 ATS 例外：`NSAllowsArbitraryLoads`、`NSAllowsLocalNetworking`。
- mitmproxy 已能看到 HTTP 的 `/api/health`、`/api/login`、`/api/order`。
- Frida 17 不能使用 `Module.findExportByName`，改用 `Module.getGlobalExportByName` / `Module.findGlobalExportByName` / `enumerateSymbols`。

因此，W4 不是重新抓 HTTP，而是：

```text
HTTP 明文已验证
→ 后端改 HTTPS
→ App 先走系统信任、不加 Pinning
→ 再打开 Pinning
→ 证明代理被阻断
→ Frida 只读观察校验点
→ 仅在自己的 App 上验证一次绕过
→ 关闭 Hook，确认 Pinning 仍然生效
```

---

## 本文件完成后的结果

完成本文件后，应当得到：

- 一份只用于本地练习的 CA 和服务器证书。
- 一个同时能开 HTTP `:5000` 和 HTTPS `:5443` 的本地后端。
- SignDemo 能请求 `https://<Mac局域网IP>:5443`。
- 一个可开关的证书固定逻辑。
- 一张三种网络状态对照表。
- 一份只读 Frida 观察脚本。
- 一份 `notes/week-04-pinning.md`。

执行顺序固定为：

```text
生成本地 CA 和服务器证书
→ 后端启用 HTTPS
→ Mac curl 验证
→ XR 安装并信任练习 CA
→ App 改 HTTPS，Pinning 关闭
→ 无代理 / 有代理 对照
→ 打开 Pinning
→ 证明 mitmproxy 被拒绝
→ 静态定位校验点
→ Frida 只读观察
→ 自己的 App 上验证一次绕过
→ 关闭 Hook 复测
→ 写笔记
```

不要一开始处理：全局 SSL Kill Switch、第三方 App Pinning、QUIC/gRPC、反调试、secret 混淆。它们属于后续周次。

---

## 执行 1：生成本地证书并启动 HTTPS 后端

### 1.1 前置条件

- 00.2 的 HTTP 后端已经能跑。
- 不要把证书私钥提交到公开仓库。
- 真机不能使用 `127.0.0.1`。证书 SAN 必须包含 **当前 Mac 局域网 IP**。

查看 IP：

```bash
ipconfig getifaddr en1 || ipconfig getifaddr en0
```

下文用 `<LAN_IP>` 表示实际值。当前常见值是 `192.168.1.8`，换网络后必须重签证书。

### 1.2 建立证书目录

```bash
cd /Users/weideshun/Desktop/SignDemo/backend
mkdir -p certs
```

### 1.3 生成练习 CA

```bash
cd /Users/weideshun/Desktop/SignDemo/backend
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout certs/ca.key \
  -out certs/ca.crt \
  -subj "/CN=SignDemo Local CA"
```

`ca.crt` 要装到 XR 上。`ca.key` 只留在 Mac，不要拷进 App。

### 1.4 生成带 IP SAN 的服务器证书

`IP.1` 必须是真实点分 IP，例如 `192.168.1.8`。不要把文档里的占位符原样写进去，否则 OpenSSL 会报 `bad ip address: value=<LAN_IP>`。

```bash
cd /Users/weideshun/Desktop/SignDemo/backend
LAN_IP="$(ipconfig getifaddr en1 || ipconfig getifaddr en0)"
echo "当前局域网 IP：$LAN_IP"

cat > certs/server.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = SignDemo Local Server

[v3_req]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
basicConstraints = CA:FALSE

[alt_names]
IP.1 = 192.168.1.8
IP.2 = 127.0.0.1
DNS.1 = localhost
EOF

openssl genrsa -out certs/server.key 2048
openssl req -new -key certs/server.key -out certs/server.csr -config certs/server.cnf
openssl x509 -req -in certs/server.csr \
  -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/server.crt -days 365 -sha256 \
  -extfile certs/server.cnf -extensions v3_req
```

检查 SAN：

```bash
openssl x509 -in certs/server.crt -noout -text | grep -A4 "Subject Alternative Name"
```

必须能看到自己的局域网 IP。如果只有 `localhost`，XR 访问 `https://<LAN_IP>` 会证书校验失败。

计算 Pinning 用的证书指纹，后面执行 4 要用：

```bash
openssl x509 -in certs/server.crt -outform DER | shasum -a 256
```

把 64 位小写十六进制记进本文件末尾的执行记录。

### 1.5 后端同时提供 HTTP 和 HTTPS

保留 `:5000` HTTP，方便对照和回退。W4 主入口改为 `:5443` HTTPS。

在 `app.py` 的 `if __name__ == "__main__":` 中按本地文件启用 TLS，例如：

```python
import os

http_port = _env_int("SIGNDEMO_PORT", 5000)
https_port = _env_int("SIGNDEMO_HTTPS_PORT", 5443)
cert = os.path.join(os.path.dirname(__file__), "certs", "server.crt")
key = os.path.join(os.path.dirname(__file__), "certs", "server.key")

# 先确认 HTTP 回退仍可用：python app.py
# HTTPS 启动示例：
# ssl_context=(cert, key)
```

推荐做法：HTTP 继续 `python app.py`；另开一个终端用：

```bash
cd /Users/weideshun/Desktop/SignDemo/backend
source .venv/bin/activate
python - <<'PY'
from app import app
app.run(host="0.0.0.0", port=5443, ssl_context=("certs/server.crt", "certs/server.key"))
PY
```

也可以把这段写进 `app.py`，用环境变量 `SIGNDEMO_TLS=1` 切换。不要删掉 HTTP 启动方式。

### 1.6 Mac 本机验证

```bash
curl -vk --cacert /Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt \
  https://127.0.0.1:5443/api/health

curl -vk --cacert /Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt \
  https://<LAN_IP>:5443/api/health
```

预期：

```json
{"ok": true, "service": "SignDemo", "time": ...}
```

不带 `--cacert` 时，系统可能提示证书不受信任，这是正常的。

### 1.7 验收标准

- [x] `certs/ca.crt`、`certs/server.crt`、`certs/server.key` 存在。
- [x] 服务器证书 SAN 包含当前局域网 IP。
- [x] `https://127.0.0.1:5443/api/health` 在 Mac 上返回 200。
- [x] `https://<LAN_IP>:5443/api/health` 在 Mac 上返回 200。
- [x] HTTP `:5000` 仍然可用。
- [x] 已记录服务器证书 SHA-256。

### 1.8 失败处理

- `unable to load certificate`：检查 `certs/` 相对路径，必须在 `backend` 目录启动。
- curl 报 `IP address mismatch`：SAN 没有写入 IP，重做 1.4。
- XR 以后换 Wi-Fi：IP 变了，必须改 `server.cnf` 后重签，并更新 App 地址。

---

## 执行 2：XR 信任练习 CA，App 改 HTTPS，Pinning 先关闭

### 2.1 把 CA 装到 XR

不要用 `127.0.0.1` 给手机下证书。在 Mac 上：

```bash
cd /Users/weideshun/Desktop/SignDemo/backend/certs
python3 -m http.server 8000
```

XR 和 Mac 同一 Wi-Fi，Safari 打开：

```text
http://<LAN_IP>:8000/ca.crt
```

然后：

```text
设置
→ 通用
→ VPN 与设备管理
→ 已下载描述文件
→ 安装 SignDemo Local CA
```

再打开完全信任：

```text
设置
→ 通用
→ 关于本机
→ 证书信任设置
→ 对 SignDemo Local CA 打开完全信任
```

装完后关掉 8000 端口的临时 HTTP 服务。

### 2.2 App 地址改为 HTTPS

修改 `SignDemo/APIConfig.m` 的默认地址：

```text
https://<LAN_IP>:5443
```

例如：

```objc
NSString * const SignDemoDefaultBaseURL = @"https://192.168.1.8:5443";
```

页面上的后端地址输入框也改成同样值。不要填 `https://127.0.0.1`。

如果 App 里还缓存着旧的 `http://...`，删除 App 或清空该输入框后再启动。

### 2.3 Pinning 先不要开

本步只验证：系统信任练习 CA 之后，HTTPS 能否通。

`APIClient` 暂时继续用默认 `NSURLSession`，不要加 `didReceiveChallenge`。

ATS：HTTPS 访问 IP 在部分 iOS 版本仍可能被拦。若请求直接失败且错误含 ATS / App Transport Security：

- 先保留现有 `NSAllowsArbitraryLoads`，把现象记进笔记。
- 不要把 ATS 例外当成 Pinning 绕过。两者不是一层。

### 2.4 真机验证

1. 启动 HTTPS 后端。
2. XR **不要开代理**。
3. Xcode 安装并打开 SignDemo。
4. 确认地址是 `https://<LAN_IP>:5443`。
5. 点 `Health`。

预期：App 显示 HTTP 200，body 含 `"service": "SignDemo"`。

Safari 也可以打开同一 URL，用于确认证书信任，不替代 App 测试。

### 2.5 验收标准

- [x] XR 已安装并完全信任 `SignDemo Local CA`。
- [x] App 默认地址是 `https://<LAN_IP>:5443`。
- [x] 无代理时 Health 成功。
- [x] 无代理时 Login / Create Test Order 仍然成功。
- [x] Pinning 代码尚未启用。

---

## 执行 3：三种网络状态对照（此时无 Pinning）

### 3.1 状态表

先在 **Pinning 关闭** 时填表。每一行都要点一次 Health。

| 编号 | 状态 | App Health | mitmweb | 结论 |
|---|---|---|---|---|
| A | 无代理、HTTPS、无 Pinning | | | |
| B | 有代理、HTTPS、无 Pinning | | | |
| C | 有代理、HTTPS、有 Pinning | 本步先空着 | 本步先空着 | 执行 4 之后再填 |

### 3.2 状态 A：无代理

XR Wi-Fi 代理设为关闭。点 Health。

预期：

- App：200。
- mitmweb：没有这次请求的明文，或根本没有这条流量。

### 3.3 状态 B：有代理、无 Pinning

这里有两层 TLS，不要混：

```text
XR ──(信任 mitmproxy CA)──► mitmproxy ──(必须信任 SignDemo Local CA)──► 后端 :5443
```

手机已经信任 mitmproxy CA 还不够。mitmproxy 作为客户端去连练习 HTTPS 时，默认不认识 `SignDemo Local CA`，会报：

```text
Certificate verify failed: unable to get local issuer certificate
server disconnect 192.168.1.8:5443
```

启动时把练习 CA 交给 mitmproxy 做上游校验：

```bash
mitmweb --listen-port 8080 \
  --set ssl_verify_upstream_trusted_ca=/Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt
```

若当前版本不认这个选项，再用：

```bash
mitmweb --listen-port 8080 --ssl-insecure
```

`--ssl-insecure` 表示不校验上游证书，只适合自己的本地后端。它不是 Pinning 绕过。

XR：

```text
Wi-Fi → 当前网络 → 配置代理 → 手动
服务器：<LAN_IP>
端口：8080
```

mitmproxy CA 在 00.2 执行 6 已经信任。若 **App** 出现证书错误，再检查：

```text
设置 → 通用 → 关于本机 → 证书信任设置
```

点 Health。

预期：

- App：200。
- mitmweb：能看到 `GET /api/health`，能看到 JSON。

这说明：系统信任链接受了 mitmproxy 签发的证书。**这还不是 Pinning。**

### 3.4 这一步不要做的事

- 不要为了看包去关 iOS 证书校验。
- 不要对系统 SSL 做全局 Hook。
- 不要开始改 `didReceiveChallenge`。

### 3.5 验收标准

- [x] 状态 A 成功，mitmweb 看不到明文。
- [x] 状态 B 成功，mitmweb 看得到明文。
- [x] 能用自己的话区分：证书不受信任、代理不通、还没有 Pinning。

---

## 执行 4：给 SignDemo 加上可开关的 Pinning

### 4.1 目标

只固定 **自己的服务器证书**。mitmproxy 再怎么被系统信任，也过不了这道比较。

Pinning 必须可开关，方便填状态 C，也方便周五恢复对照。

### 4.2 建议改动位置

不要把逻辑散落在 `ViewController`。继续用现有网络类：

```text
APIConfig.h / APIConfig.m     开关和指纹常量
APIClient.m                   使用带 delegate 的 NSURLSession
新建 PinningURLSessionDelegate.h/.m
把 server.crt 拷进 App Bundle，或只硬编码 SHA-256
```

`APIConfig` 增加：

```objc
FOUNDATION_EXPORT BOOL SignDemoPinningEnabled;
FOUNDATION_EXPORT NSString * const SignDemoPinnedCertSHA256;
```

```objc
BOOL SignDemoPinningEnabled = YES;
NSString * const SignDemoPinnedCertSHA256 = @"<执行1记下的64位hex>";
```

页面上可以加一个 `Pinning ON/OFF` 开关；没有 UI 也可以先改常量后重新编译。

### 4.3 校验逻辑要求

在 `NSURLSessionDelegate` 的：

```objc
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler;
```

中实现：

1. 只处理 `NSURLAuthenticationMethodServerTrust`。
2. 从 `challenge.protectionSpace.serverTrust` 取出服务器证书。
3. 计算 DER 的 SHA-256，和小写十六进制指纹比较。
4. 开关关闭：走系统默认信任，或直接使用 `NSURLCredential`。
5. 开关打开且指纹匹配：`NSURLSessionAuthChallengeUseCredential`。
6. 开关打开且指纹不匹配：`NSURLSessionAuthChallengeCancelAuthenticationChallenge`。
7. 失败时让 App 文本区能看到错误，不要静默失败。

不要：

- 无条件 `completionHandler(NSURLSessionAuthChallengeUseCredential, ...)`。
- Hook 系统全局 SSL。
- 把 mitmproxy 证书写进 Pin 列表。

创建 session 时必须设置 delegate，否则这个方法不会被调用：

```objc
_session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                         delegate:self.pinningDelegate
                                    delegateQueue:nil];
```

默认 `sessionWithConfiguration:` 没有 delegate，Pinning 代码写了也不会执行。

### 4.4 把证书放进工程时注意

如果选择拷贝 `server.crt`：

- 只拷 `server.crt`，不要拷 `ca.key` / `server.key`。
- 确认 Xcode Target Membership 包含该文件。
- 不要把 `backend/.venv` 再拖进 App 目录。

更稳妥的第一版是只硬编码 SHA-256 字符串，不把私钥或完整证书链打进包里。

### 4.5 无代理、Pinning 打开

XR 代理关闭。`SignDemoPinningEnabled = YES`。点 Health。

预期：200。因为对端就是被 Pin 的那张服务器证书。

### 4.6 有代理、Pinning 打开（状态 C）

XR 重新打开 mitmproxy 代理。点 Health。

预期：

- App：失败。错误类似证书校验失败、cancelled、或自定义的 `pinning mismatch`。
- mitmweb：看不到完整明文业务 JSON，或只能看到 TLS 握手失败。

把结果填进执行 3 的状态 C。

### 4.7 验收标准

- [x] Pinning 有明确开关。
- [x] 无代理 + Pinning ON：Health 成功。
- [x] 有代理 + Pinning ON：Health 失败。
- [x] 把开关改回 OFF 并重装后，有代理又能抓到明文。
- [x] 能说明：系统信任 mitmproxy CA，不等于 App 接受这张证书。

---

## 执行 5：静态定位 + Frida 只读观察

### 5.1 静态阅读

在 Xcode 里搜索：

```text
didReceiveChallenge
serverTrust
SecTrustEvaluate
pinned
SHA256
NSURLAuthenticationMethodServerTrust
```

记录：

```text
类名：
方法名：
开关变量：
比较的是整张证书还是公钥：
失败时 disposition：
```

以当前工程实际类名为准。不要照抄网上的 `AFSecurityPolicy` 或 Alamofire 例子，除非你真的加了这些库。当前 SignDemo 没有这些库。

### 5.2 观察脚本

文件：

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js
```

第一阶段只打印，不改返回值。

必须观察：

- 自己的 `didReceiveChallenge` 是否被调用。
- `protectionSpace.host`、`authenticationMethod`。
- Pinning 开关当前值（如果是 ObjC 全局/属性）。
- 计算出的指纹或比较结果。
- `completionHandler` 走的是 UseCredential 还是 Cancel。

可选观察：

- `SecTrustEvaluateWithError`

Frida 17 注意：

```javascript
// 不要用 Module.findExportByName
const addr = Module.getGlobalExportByName("SecTrustEvaluateWithError");
```

如果 `getGlobalExportByName` 抛错，再用 `Process.enumerateModules()` 后 `enumerateSymbols()`。

ObjC Hook 以实际类名为准，例如：

```javascript
const Delegate = ObjC.classes.PinningURLSessionDelegate;
const sel = "- URLSession:didReceiveChallenge:completionHandler:";
Interceptor.attach(Delegate[sel].implementation, {
  onEnter(args) {
    const challenge = new ObjC.Object(args[3]);
    console.log("[+] didReceiveChallenge");
    console.log("    host = " + challenge.protectionSpace().host());
    console.log("    method = " + challenge.protectionSpace().authenticationMethod());
  }
});
```

类名以 Xcode 里最终文件为准。

### 5.3 运行

XR 解锁。Pinning ON。先无代理 spawn：

```bash
frida -U -f com.weideshun.SignDemo \
  -l /Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js
```

若停住，输入 `%resume`。点 Health。

再开代理，再点一次 Health。

预期：

- 无代理：方法被调用，比较成功。
- 有代理：方法被调用，比较失败。
- 脚本没有 `replace` 返回值，失败时 App 仍然失败。

### 5.4 记录模板

```text
目标方法：
所在类：
触发动作：无代理 Health / 有代理 Health
进入次数：
host：
authenticationMethod：
指纹比较结果：
UI 结果：
是否与源码判断一致：
```

### 5.5 验收标准

- [x] 能指出 Pinning 代码的类和方法。
- [x] Frida 证明 `didReceiveChallenge` 确实执行。
- [x] 有代理和无代理都能看到不同比较结果。
- [x] 观察阶段没有改返回值。

### 5.6 失败处理

- 脚本无输出：session 可能没设置 delegate；先确认 `APIClient` 创建 session 时传入了 delegate。
- `TypeError: not a function`：又用了 Frida 16 的 `Module.findExportByName`。
- 找不到类：`Object.keys(ObjC.classes).filter(x => x.toLowerCase().indexOf("pinning") !== -1)`。
- spawn 后闪退：先只 `console.log` 类名，不读未知指针。

---

## 执行 6：仅在自己的 App 上验证绕过，然后恢复

### 6.1 范围

只允许对 `com.weideshun.SignDemo` 做这次实验。不要对系统 App、商店 App 或 UnCrackable 做 SSL 绕过。

### 6.2 绕过方式

在观察脚本确认调用栈之后，再复制一份：

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/bypass_signdemo_pinning.js
```

最小改法：在自己的 `didReceiveChallenge` 里，对 `completionHandler` 改为 `UseCredential`。不要批量 Hook 所有 `SecTrustEvaluate*` 作为本周主线。

做之前先保存一份“Pinning ON + 代理 + 无 Hook”的失败记录。

### 6.3 验证

Pinning ON，XR 代理指向 mitmproxy：

1. 不加载 bypass 脚本：Health 失败。
2. 加载 bypass 脚本：Health 成功，mitmweb 能看到明文。
3. 退出 Frida，不附加任何脚本，再点 Health：必须再次失败。

第 3 步不通过，说明 Pinning 被写死绕过或开关被关掉，不能算完成。

### 6.4 恢复

- 停止 Frida。
- `SignDemoPinningEnabled` 保持可打开。
- 不要把 bypass 作为 App 默认逻辑提交进主路径。
- 练习用私钥继续只放在 `backend/certs/`。
- 本周结束后，XR 上的练习 CA 可以保留到 W5，但要在笔记里标明这是本地实验 CA。

### 6.5 验收标准

- [x] 能证明：同一套 Pinning，无 Hook 时拦代理，有 Hook 时放行。
- [x] 退出 Hook 后 Pinning 重新生效。
- [x] 没有对第三方 App 做绕过。
- [x] 笔记写明这是自己的靶场实验，不是通用破解教程。

---

## 执行 7：写 W4 笔记

### 7.1 文件

```text
notes/week-04-pinning.md
```

建议放在工作区：

```text
/Users/weideshun/Downloads/ll/notes/week-04-pinning.md
```

或 SignDemo 旁的 `notes/`。选一个位置写进执行记录，不要两份互相覆盖。

### 7.2 必须包含

```markdown
# W4 SignDemo TLS Pinning

## 环境
- 日期：
- 设备：iPhone XR / iOS 18.5
- App：com.weideshun.SignDemo
- 后端：https://<LAN_IP>:5443
- Frida：17.17.0

## 证书
- CA 指纹或 CN：
- 服务器证书 SHA-256：
- SAN：

## 三种状态
| 状态 | App | mitmproxy | 结论 |
|---|---|---|---|

## Pinning 实现
- 类：
- 方法：
- 比较对象：

## Frida 观察
- 无代理输出：
- 有代理输出：

## 绕过实验
- 修改了什么：
- 恢复后是否仍失败：

## 未验证项

## 下一步
```

脱敏：

- 不写真实账号。
- 测试 Token 可保留，标注为虚构。
- 不要把 `ca.key` / `server.key` 贴进笔记。

### 7.3 产物清单

```text
SignDemo/backend/certs/ca.crt
SignDemo/backend/certs/server.crt
SignDemo/scripts/frida/observe_signdemo_trust.js
notes/week-04-pinning.md
```

可选：`bypass_signdemo_pinning.js`，必须标注仅用于自己的 SignDemo。

### 7.4 验收标准

- [x] 能说明 Pinning 与系统 CA 信任的区别。
- [x] 能证明 SignDemo 的 Pinning 开关确实生效。
- [x] 能用 Frida 在自己的 App 上观察到校验点。
- [x] 能恢复到未注入状态并重新验证。
- [x] 笔记完成并且数据已脱敏。

---

## 全部完成后的最终检查

```bash
# 后端 HTTPS
curl -vk --cacert /Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt \
  https://<LAN_IP>:5443/api/health

# App 无代理 + Pinning ON：Health 成功
# App 有代理 + Pinning ON + 无 Frida：Health 失败
# App 有代理 + Pinning ON + bypass 脚本：Health 成功且 mitmweb 可见
# 退出 Frida 后再点 Health：再次失败

frida -U -f com.weideshun.SignDemo \
  -l /Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js
```

确认文件存在：

```text
/Users/weideshun/Desktop/SignDemo/backend/certs/server.crt
/Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js
notes/week-04-pinning.md
```

下一阶段进入 [`05-W5-协议可见性-详细执行步骤.md`](05-W5-协议可见性-详细执行步骤.md)。W4 结束后不要急着给 SignDemo 加越狱检测。

---

## 和 00.2 的关系

| 00.2 | W4 |
|---|---|
| HTTP `:5000` | 保留作回退，主测试改为 HTTPS `:5443` |
| ATS 例外让 HTTP 能发 | 例外不是 Pinning 绕过 |
| mitmproxy 能看到明文 | 无 Pinning 时仍能看到；有 Pinning 时应该看不到 |
| Frida 观察 UnCrackable / 签名 | Frida 观察 `didReceiveChallenge` |
| 真机不用 `127.0.0.1` | 证书 SAN 和 App 地址同样不能用 `127.0.0.1` |

---

## 执行记录

### 执行 1：证书和 HTTPS 后端

```text
日期：
局域网 IP：
SAN：
HTTPS 端口：
Mac curl health：
服务器证书 SHA-256：
结果：
```

### 执行 2：App 接入 HTTPS

```text
XR 是否安装练习 CA：
是否打开完全信任：
App 默认地址：
无代理 Health：
Pinning 是否仍关闭：
结果：
```

### 执行 3：无 Pinning 对照

```text
状态 A App / mitmweb：
状态 B App / mitmweb：
结果：
```

### 执行 4：打开 Pinning

```text
开关位置：
无代理 + Pinning ON：
有代理 + Pinning ON：
关掉开关后代理是否恢复明文：
结果：
```

### 执行 5：Frida 观察

```text
类名：
方法名：
spawn 命令：
无代理输出：
有代理输出：
是否改返回值：否
结果：
```

### 执行 6：绕过和恢复

```text
bypass 脚本：
Hook 时代理 Health：
退出 Hook 后 Health：
结果：
```

### 执行 7：笔记

```text
笔记路径：
观察脚本路径：
是否脱敏：
结果：
```
