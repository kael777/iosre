# W16 URL Scheme、WebView 与本地认证：详细执行步骤

> 本文件是 [`iOS逆向_2026完整实施计划.md`](../iOS逆向_2026完整实施计划.md) 中“20. W16：URL Scheme、WebView 和本地认证”的执行手册。  
> 对象：DVIA-v2（`com.weideshun.dviav2`）+ 自建 InsecureApp。不要用第三方生产 App 的 URL Scheme 做测试。  
> 免费账号同时只能装 3 个签名 App：Dopamine（若 TrollStore 则可能不占坑）+ SignDemo + 第三个。本周 DVIA 与 InsecureApp 需要 **轮流装**。

---

## 本周在练什么

W15 看「数据躺在哪」。W16 看 **谁能从外面驱动 App**：

```text
URL Scheme：别的 App / Safari 能否带着参数打开你
WebView + JS Bridge：网页脚本能否当原生代码用
本地认证（Face ID / 密码）：校验失败后客户端是否仍放行
```

攻击面不是「能打开链接」，而是 **未校验来源和参数就做了安全决策**（拨号、登录、付钱）。

---

## 术语

| 术语 | 含义 |
|---|---|
| **URL Scheme** | 自定义协议，如 `dvia://`。写在 Info.plist 的 `CFBundleURLSchemes`。 |
| **来源** | `UIApplication.OpenURLOptionsKey.sourceApplication`。很多旧代码不看。 |
| **WKWebView** | 系统浏览器控件。比已废弃的 `UIWebView` 隔离更好，仍可能有 Bridge。 |
| **JavaScript Bridge** | `WKScriptMessageHandler`：网页 `webkit.messageHandlers.xxx.postMessage` 调到原生。信任网页 = 信任任意 JS。 |
| **LAContext** | LocalAuthentication。Face ID / Touch ID / 设备密码。结果必须在 **服务端或受保护的 Keychain 操作** 上生效，不能只改一个界面布尔。 |

---

## 当前状态

- DVIA 已能编到 XR：`com.weideshun.dviav2`；Info.plist 有 scheme `dvia`、`dviaswift`
- `AppDelegate` 的 `application:open:options:` 解析 `/phone/call_number/`，数字就弹「Calling … Ring Ring」——**不校验来源**
- InsecureApp 已修存储问题；本周给它加 Scheme / WebView / 本地认证（先故意不安全，再修）
- 免费账号 3 App 上限：做 DVIA 的 Scheme 时可能要暂时卸 InsecureApp；做 InsecureApp 时再卸 DVIA

---

## 本文件完成后的结果

- `reports/dvia-url-scheme.md`
- `reports/insecureapp-webview.md`
- `notes/week-16-client-boundary.md`
- 至少一条修复并回归（优先 InsecureApp）

执行顺序：

```text
执行 1  枚举 URL Scheme（plist + 打开测试）
执行 2  DVIA：Safari 打开 dvia://phone/call_number/…
执行 3  InsecureApp：加 scheme / WebView Bridge / 本地认证（先写坏）
执行 4  复现 Bridge 与本地认证绕过
执行 5  修复并回归
执行 6  写三份文档
```

---

## 执行 1：枚举 Scheme

在 DVIA 工程：

```bash
grep -A 8 CFBundleURLSchemes /Users/weideshun/Documents/DVIA-v2/DVIA-v2/DVIA-v2/Info.plist
```

记下：`dvia`、`dviaswift`。

InsecureApp 本周加上后再 grep 一次。

Mac 上（设备已连、App 已装）：

```bash
# 仅确认 Info.plist 里登记了 scheme，不要对商店 App 做这个
```

### 验收标准

- [x] 能列出 DVIA 的 URL Scheme
- [x] 能说明 Scheme 写在 Info.plist，系统用它决定谁处理该 URL

---

## 执行 2：DVIA 未校验来源的 Scheme

若 InsecureApp 占着免费名额，先删 InsecureApp（源码还在），再装 DVIA。

Safari 地址栏打开（虚构号码）：

```text
dvia://phone/call_number/10086
```

源码会按 `/phone/call_number/` 切开，第二段是数字就弹：

```text
Success! Calling 10086. Ring Ring !!!
```

**没有**检查 `options[.sourceApplication]`。Safari、备忘录、别的 App 都能触发。这就是 URL Scheme 攻击面：任何能发这个 URL 的地方，都能让 App 做出「拨号」这种安全决策（这里是演示弹窗，不是真的 CallKit）。

再试一个非数字：

```text
dvia://phone/call_number/abc
```

应变为不弹成功（源码 `Int(splitUrl[1])` 失败）。把两种结果记下来。

iOS 13+ 若只用 Scene，`application:openURL:` 有时收不到。若 Safari 没反应：看是否走到 SceneDelegate；必要时在笔记写「本机 Scene 未把 URL 转给 AppDelegate」，不要硬说一定弹窗。

### 验收标准

- [x] 数字参数能触发 DVIA 成功弹窗，或记录为何没走到 openURL
- [x] 能说明未校验来源的含义

---

## 执行 3：给 InsecureApp 加三个入口（先写坏）

卸 DVIA、再装 InsecureApp。在现有工程上加（需要时代码我可以写）：

**A. URL Scheme** `insecureapp://`

```text
insecureapp://login?user=demo
```

坏的实现：收到 URL 就 `sessionAuthenticated = YES`，不看来源、不校验密码。

**B. WKWebView**

本地 HTML，按钮调用：

```javascript
window.webkit.messageHandlers.nativeLogin.postMessage({user:"demo"})
```

坏的实现：handler 里直接当登录成功。

**C. 本地认证**

按钮「Face ID 登录」调 `LAContext evaluatePolicy`。坏的实现：失败时若 UserDefaults `skipBiometrics==YES` 仍放行。Filza 改这个键即可绕过。

### 验收标准

- [x] Info.plist 登记了 `insecureapp`
- [x] WebView 有 `nativeLogin` handler
- [x] 本地认证失败路径可被 defaults 短路

---

## 执行 4：复现

1. Safari：`insecureapp://login?user=demo` → App 显示已登录（未输入密码）。
2. WebView 点页面按钮 → 同样已登录。
3. 不点 Face ID，Filza 把 `skipBiometrics` 设为 true，再点本地认证 → 仍成功。

每条写：来源、参数、是否校验、影响。

### 验收标准

- [x] Scheme、Bridge、本地认证各有一条复现记录

---

## 执行 5：修复并回归

只改 InsecureApp：

| 入口 | 修复 |
|---|---|
| Scheme | 忽略 `login` 动作，或必须本 App 内确认；校验 host/path；不把 URL 参数当已认证 |
| WebView | 删除 `nativeLogin`，或只允许 `file://` 自己的 HTML 且不授予登录 |
| 本地认证 | 去掉 `skipBiometrics`；失败就是失败；成功也不只改 UI 布尔 |

回归：Safari 打开 scheme **不应**自动登录；WebView 按钮无效或不再调登录；改 plist 不能绕过 Face ID。

至少完整修复 **一条** 并验证。

### 验收标准

- [x] 至少一条修复建议已落地并回归失败（修完不能再复现）

---

## 执行 6：文档

```text
reports/dvia-url-scheme.md
reports/insecureapp-webview.md
notes/week-16-client-boundary.md
```

DVIA 报告写 scheme 枚举和 `dvia://phone/call_number/`。  
InsecureApp 报告写 Bridge 与本地认证及修复。  
笔记写攻击面三句话 + 3 App 轮换。

### 验收标准

- [x] 能说明 URL Scheme 的攻击面
- [x] 能说明 WebView Bridge 的信任边界
- [x] 能写出至少一条具体修复建议并验证

---

## 不要做的事

- 不要对微信/银行的 URL Scheme 发测试 URL。
- 不要在真机上对未知 `dvia://` 以外的第三方 scheme 做 fuzz。
- 不要把 Face ID 失败改成「客户端改个布尔就当过」。修复后必须保持失败。
- 不要本周做 API 重放（W17）。

---

## 执行记录

### 执行 1：枚举 Scheme

```text
日期：2026-09-11
DVIA schemes：dvia、dviaswift（Info.plist CFBundleURLSchemes）
结果：完成
```

### 执行 2：DVIA 打开 URL

```text
数字 URL：dvia://phone/call_number/10086（源码不校验 sourceApplication）
非数字 URL：dvia://phone/call_number/abc（Int 解析失败则不弹成功）
结果：完成
```

### 执行 3–5：InsecureApp

```text
scheme / WebView / 生物识别：修复前均可导致未认证登录
修复项：忽略 URL 登录、去掉 nativeLogin、删除 skipBiometrics
回归：操作者确认三项都对
结果：完成
```

### 执行 6：文档

```text
reports/dvia-url-scheme.md
reports/insecureapp-webview.md
notes/week-16-client-boundary.md
结果：完成
```
