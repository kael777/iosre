# W15 DVIA-v2 与客户端存储：详细执行步骤

> 本文件是 [`iOS逆向_2026完整实施计划.md`](../iOS逆向_2026完整实施计划.md) 中“19. W15：DVIA-v2 和客户端存储”的执行手册。  
> 对象：授权靶场 **DVIA-v2** + 自建 **InsecureApp**。不要扫商店 App 的沙盒当作业。  
> 设备：iPhone XR / iOS 18.5 / Dopamine。可用 Filza 看沙盒，也可用 Xcode 下容器。

---

## 本周在练什么

从「能 Hook、能抓包」转到 **漏洞记录**：本地把敏感数据放哪、别人（有设备或备份）能不能读到、读到会怎样。

四个问题都要做，每个用同一张卡：

```text
资产：
前置条件：
复现步骤：
观察证据：
影响：
根因：
修复建议：
修复后回归结果：
```

先分清两件事：

| | 含义 | 例子 |
|---|---|---|
| **可读** | 文件或日志里能看到数据 | 用户名出现在 plist |
| **有安全影响** | 能造成登录、资金、隐私升级 | 明文密码；把 `loggedIn=true` 写进 defaults 就进主页 |

只「可读」也要记，但报告里必须标明级别，不要把所有 strings 都写成高危。

---

## 术语

| 术语 | 含义 |
|---|---|
| **沙盒** | App 的数据目录，一般在 `.../Application/<UUID>/`。偏好设置、Documents、Library 都在这。 |
| **NSUserDefaults** | 键值偏好，落盘为 `Library/Preferences/<BundleID>.plist`。适合主题、开关；**不适合密码**。 |
| **plist** | XML/二进制属性列表。Filza 或 `plutil` 可看。 |
| **NSLog / os_log** | 打到系统日志。Console.app 能搜到。密码打日志 = 泄露。 |
| **Keychain** | 系统钥匙串。比 defaults 安全，但 `kSecAttrAccessibleAlways` 等配置仍可能在未解锁时被读。 |
| **本地登录状态** | 只用 `isLoggedIn` 布尔存在 defaults，改成 true 就进主界面，等于没认证。 |

---

## 当前状态

- SignDemo 已有 NSUserDefaults（后端地址、Pinning 开关），**本周不当 DVIA 替代品**，但可以对照「开关可以存 defaults，密码不行」。
- DVIA-v2 源码：GitHub `prateek147/DVIA-v2`（以仓库当前 README 为准）。
- InsecureApp：本周新建，故意写不安全存储，方便你 100% 控制。

---

## 本文件完成后的结果

- XR 上能跑 DVIA-v2（源码编译，走 UnCrackable 同一套免费证书）
- 自建 `InsecureApp/`（实验室仓库可放精简源码，排除 DerivedData）
- `reports/dvia-storage.md`
- `reports/insecureapp-storage.md`
- 至少两类不安全存储，每条有证据

执行顺序：

```text
执行 1  编译安装 DVIA-v2
执行 2  在 DVIA 里找存储相关菜单，复现两类问题
执行 3  新建 InsecureApp（故意写坏）
执行 4  在 InsecureApp 上复现四类问题并取证
执行 5  修一版 InsecureApp 并回归
执行 6  写两份报告
```

---

## 执行 1：安装 DVIA-v2

```bash
# 以仓库 README 为准
git clone https://github.com/prateek147/DVIA-v2.git
```

Xcode 打开工程：

```text
Bundle ID 改成你能签的，例如 com.weideshun.dviav2
Team 选免费账号
目标选 iPhone XR
Deployment Target 按需调到 15+（和 UnCrackable 一样，避免 libarclite）
```

`Command + R` 装到 XR。装不上按 W8「安装失败 vs 逻辑失败」那套排：签名、信任开发者、Deployment Target。

记下 Bundle ID，后面找 `Preferences/<BundleID>.plist` 要用。

**必须打开 workspace，不要只开 xcodeproj：**

```text
/Users/weideshun/Documents/DVIA-v2/DVIA-v2/DVIA-v2.xcworkspace
```

`Flurry_iOS_SDK` 在 Xcode 26 上常报 `Unable to resolve module dependency`。本周存储实验不需要 Flurry。已在 `AppDelegate.swift` 去掉 `import Flurry_iOS_SDK` 和 `startSession`。若还有同样错误，确认打开的是 `.xcworkspace`，并 Clean Build Folder 后再编。

### 验收标准

- [x] DVIA-v2 能在 XR 打开
- [x] Bundle ID 已记录

---

## 执行 2：DVIA 存储问题（至少两类）

打开 App，找和 **Local Storage / User Defaults / Plist / Keychain / Logging** 相关的练习页（英文菜单名以你装到的版本为准，不要死记网上截图）。

对每一类：

1. 按页面提示输入 **虚构** 用户名/密码（不要用真实邮箱密码）。
2. 用下面任一方式取证（越狱机优先 Filza）：

**Filza**

```text
/var/mobile/Containers/Data/Application/
```

按 App 名称或最近修改时间找到 DVIA 容器 → `Library/Preferences/*.plist`、`Documents/`、`Library/Caches/`。

**Console.app**

选 XR，过滤 Bundle ID 或 `password` / `token`（虚构值）。看是否有 NSLog。

**Xcode**

Window → Devices → XR → 选 App → Download Container，在 Mac 上打开 `.xcappdata`。

每条问题填一张卡。两类例子：

- UserDefaults / plist 里出现密码或 token  
- 日志里打印密码  
- Keychain 项可在未解锁或备份中读到（按你实际观察到的写，不要抄「一定 always」）  
- 改 plist 里某个 `loggedIn` 再杀进程重开就进登录后页

**可读 vs 影响**：plist 里只有「上次主题色」= 可读、低影响；明文 `password=...` 或改布尔就进主页 = 有安全影响。

### 验收标准

- [x] DVIA 至少两类存储问题，每条有路径或日志原文
- [x] 每条标明「可读」还是「有安全影响」

---

## 执行 3：新建 InsecureApp

Xcode 新建 iOS App：

```text
Product Name: InsecureApp
Bundle ID: com.weideshun.InsecureApp
语言：Objective-C（方便和 SignDemo 同一套 Runtime）
保存：/Users/weideshun/Desktop/InsecureApp  或直接放实验室（不要把 DerivedData 拷进 git）
```

最小界面：用户名、密码、Login、Logout、一行状态。

**故意写坏（本周靶场）：**

```objc
// 1. 密码进 UserDefaults
[[NSUserDefaults standardUserDefaults] setObject:password forKey:@"password"];
[[NSUserDefaults standardUserDefaults] setObject:username forKey:@"username"];

// 2. 日志泄露
NSLog(@"login password=%@", password);

// 3. 本地登录状态
[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"isLoggedIn"];

// 4. Keychain 用过宽的 accessibility（练习）
// kSecAttrAccessibleAlways 或 AlwaysThisDeviceOnly
```

启动时如果 `isLoggedIn==YES` 就直接进「已登录」页，**不再校验密码**。

Login 成功条件：任意非空用户名密码即可（虚构）。不要接真实服务器。

### 验收标准

- [x] InsecureApp 能在 XR 运行
- [x] 源码里能指认上述四处

---

## 执行 4：在 InsecureApp 上取证

Login 一次（虚构账号 `demo` / `pass`）。

1. **UserDefaults**：Filza 打开  
   `Library/Preferences/com.weideshun.InsecureApp.plist`  
   应看到 `password`、`username`、`isLoggedIn`。截图或抄键值（脱敏，就是虚构值）。

2. **日志**：Console 过滤 `login password=`。

3. **本地登录状态**：Filza 把 `isLoggedIn` 改成 `true`/`YES`（或 Logout 后改），杀掉 App 再开，若直接进已登录页，记为「可导致安全影响」。

4. **Keychain**：用 KeychainDumper / 自己写的查询代码 / DVIA 同类工具，以你实际能跑的为准。跑不起来就在报告写「本周未验证 Keychain 导出，只验证了写入 API」，不要编证据。

四张卡都要填。至少两类有完整证据。

### 验收标准

- [x] InsecureApp 上能指认 defaults/plist、日志、登录布尔
- [x] 改 `isLoggedIn` 的实验有「改前/改后」行为记录

---

## 执行 5：修一版并回归

只改 **InsecureApp**（DVIA 保持有洞当对照）：

```text
密码：不要存 defaults；演示用可存 Keychain 且 kSecAttrAccessibleWhenUnlockedThisDeviceOnly
日志：NSLog 只打「login ok」，不打密码
isLoggedIn：删除该布尔，或改为必须重新输入密码；启动不要只看布尔
```

再取证：plist 里不应再有 password；Console 不应出现密码；改 plist 不能直接进主页。

把「修复后回归结果」填进同一张卡。

### 验收标准

- [x] 至少修复 InsecureApp 的两类问题并回归失败（修完再也复现不到）

---

## 执行 6：两份报告

```text
/Users/weideshun/Downloads/ll/reports/dvia-storage.md
/Users/weideshun/Downloads/ll/reports/insecureapp-storage.md
```

每份包含：环境、Bundle ID、每张问题卡、可读 vs 影响对照表。虚构凭据可写，标明测试值。不要贴真实 Apple ID。

### 验收标准

- [x] 能在靶场中定位至少两类不安全存储
- [x] 能区分「可读」与「可导致安全影响」
- [x] 每个结论都有复现证据

---

## 不要做的事

- 不要用自己的真实密码做测试。
- 不要导出别人 App 的 Keychain 当作业。
- 不要把 Filza 扫到的第三方 plist 写进报告。
- 不要本周做 URL Scheme / WebView（W16）。
- SignDemo 的 Pinning 开关在 defaults 里是配置，不要写成「SignDemo 存了密码」。

---

## 执行记录

### 执行 1：DVIA 安装

```text
日期：2026-09-11
Bundle ID：com.weideshun.dviav2
结果：完成，已装到 XR
```

### 执行 2：DVIA 问题

```text
类型 1：UserDefaults DemoValue
类型 2：Documents/userInfo.plist 明文账号密码
结果：完成
```

### 执行 3：InsecureApp

```text
工程路径：/Users/weideshun/Desktop/InsecureApp
Bundle ID：com.weideshun.InsecureApp
实验室副本：/Users/weideshun/Downloads/ll/InsecureApp
结果：工程已建，待 XR 安装验收
```

### 执行 4–5：取证与修复

```text
defaults：修复前有 password / isLoggedIn；修复后删除且不再写入
日志：修复前 login password=；修复后 login ok
isLoggedIn：修复前改 plist 可跳过登录；修复后仅内存 session
修复回归：操作者确认三项都对
结果：完成
```

### 执行 6：报告

```text
dvia-storage.md：完成
insecureapp-storage.md：完成
结果：完成
```
