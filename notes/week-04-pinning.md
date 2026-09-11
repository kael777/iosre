# W4 SignDemo TLS Pinning

## 环境

- 日期：2026-09-10
- 设备：iPhone XR / iOS 18.5 / arm64e / Dopamine
- Mac：Mac mini 2023（Apple M2）/ macOS 26.6.2 / Xcode 26.6
- App：`com.weideshun.SignDemo`
- 后端：`https://192.168.1.8:5443`（HTTP `:5000` 保留作回退）
- 后端路径：`/Users/weideshun/Desktop/SignDemo/backend/`
- Frida：17.17.0
- mitmproxy：12.2.3，监听 `8080`

账号、密码、订单均为虚构测试数据，不是真实凭据。

## 证书

练习 CA 和服务器证书只用于本机 SignDemo，私钥未写入笔记、未打进 App。

- CA CN：`SignDemo Local CA`
- CA SHA-256（openssl fingerprint）：`3E:1C:5F:8C:8E:A6:B6:E8:09:8A:C3:6D:46:02:9D:7B:9D:63:80:1F:C1:DE:19:E0:35:1E:F6:B7:56:F0:3C:3D`
- 服务器 CN：`SignDemo Local Server`
- 服务器证书 DER SHA-256（App Pinning 使用）：`ff85926af95e4574fbb47e19ffd4ad6ce90dfb6012d84e0effb995904dd377ce`
- SAN：`IP Address:192.168.1.8, IP Address:127.0.0.1, DNS:localhost`

XR 已安装并完全信任 `SignDemo Local CA`。真机地址不能用 `127.0.0.1`。换 Wi-Fi 后 IP 变化需要重签证书，并更新 `APIConfig.m` 里的指纹。

## 三种状态

| 状态 | App Health | mitmproxy | 结论 |
|---|---|---|---|
| 无代理、HTTPS、无 Pinning | 成功 | 无明文 | 系统信任练习 CA，直连后端 |
| 有代理、HTTPS、无 Pinning | 成功 | 能看到 `/api/health` JSON | 系统也信任 mitmproxy CA，代理可以冒充后端 |
| 有代理、HTTPS、有 Pinning | 失败，指纹不匹配 | 看不到业务 JSON | App 不接受 mitmproxy 现场签发的证书 |

补充：有代理时，mitmproxy 自己连 `https://192.168.1.8:5443` 也必须认识练习 CA。否则会报 `unable to get local issuer certificate`。这是代理的上游 TLS，不是 App Pinning。启动方式：

```bash
mitmweb --listen-port 8080 \
  --set ssl_verify_upstream_trusted_ca=/Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt
```

## Pinning 实现

- 类：`PinningURLSessionDelegate`
- 方法：`- URLSession:didReceiveChallenge:completionHandler:`
- 开关：页面 `证书 Pinning`，对应 `pinningEnabled` / `SignDemoPinningEnabled`
- 比较对象：叶子证书 DER 的 SHA-256，不是公钥、不是 mitmproxy CA
- 指纹常量：`SignDemoPinnedCertSHA256`（`APIConfig.m`）
- 打开且匹配：`NSURLSessionAuthChallengeUseCredential`
- 打开且不匹配：`NSURLSessionAuthChallengeCancelAuthenticationChallenge`，文本区显示 expected / actual
- 关闭：`NSURLSessionAuthChallengePerformDefaultHandling`（走系统 CA）
- `NSURLSession` 创建时必须带这个 delegate，否则回调不会执行

系统信任回答「这张证书像不像合法证书」。Pinning 回答「这张证书是不是我指定的那一张」。ATS 例外、用户点「信任证书」、`--ssl-insecure` 都不是 Pinning。

## Frida 观察

脚本：`/Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js`

只打印，不改返回值。Frida 17 不能使用 `Module.findExportByName`。

```bash
frida -U -f com.weideshun.SignDemo \
  -l /Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js
```

- 无代理、Pinning ON：`didReceiveChallenge` 被调用，`pinningEnabled = true`，指纹 match，`completionHandler = UseCredential`，Health 成功。
- 有代理、Pinning ON：同样进入该方法，指纹不匹配，`completionHandler = CancelAuthenticationChallenge`，Health 仍失败。

## 绕过实验

脚本：`/Users/weideshun/Desktop/SignDemo/scripts/frida/bypass_signdemo_pinning.js`  
范围：仅 `com.weideshun.SignDemo`。不是通用破解，也不对第三方 App 使用。

最终改法：不包装 `completionHandler`，不 Hook getter/setter。等脚本加载完成后再挂 `-didReceiveChallenge:`，在进入时对该实例调用 `setPinningEnabled_(0)`，让源码走系统信任。

| 步骤 | 结果 |
|---|---|
| Pinning ON + 代理 + 无 Hook | Health 失败 |
| Pinning ON + 代理 + bypass 脚本 | Health 成功，mitmweb 可见明文 |
| 退出 Frida 后再点 Health | 再次失败，Pinning 仍生效 |

中间失败记录（避免以后再踩）：

- 包装 `completionHandler` / `setLastFailureReason_(null)`：Frida 17 上闪退。
- spawn 阶段调用 `NSBundle.mainBundle()`、Hook `pinningEnabled` getter/setter：脚本还没加载完就 `the connection is closed`。
- 可用的 spawn 方式：启动时不发 ObjC 消息，`setImmediate` 后再 Hook。

不要把 bypass 写进 App 默认逻辑。私钥继续只放在 `backend/certs/`。

## 产物

```text
/Users/weideshun/Desktop/SignDemo/backend/certs/ca.crt
/Users/weideshun/Desktop/SignDemo/backend/certs/server.crt
/Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js
/Users/weideshun/Desktop/SignDemo/scripts/frida/bypass_signdemo_pinning.js
/Users/weideshun/Downloads/ll/notes/week-04-pinning.md
```

`ca.key` / `server.key` 不进入笔记。

## 未验证项

- 未对第三方 App 做 Pinning 绕过（本周明确不做）。
- 未使用全局 SSL Kill Switch。
- 未验证证书轮换 / 公钥 Pinning。
- 局域网 IP 变化后的重签流程，本周未实际换网络。

## 下一步

进入主计划 W5：WebSocket、HTTP/2、QUIC 和 gRPC。W4 结束后不要急着给 SignDemo 加越狱检测。XR 上的练习 CA 可以暂时保留，但要记住这是本地实验 CA。
