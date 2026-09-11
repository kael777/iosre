# InsecureApp 客户端存储

## 环境

- 日期：2026-09-11
- Bundle ID：`com.weideshun.InsecureApp`
- 工程：`/Users/weideshun/Desktop/InsecureApp`
- 实验室副本：`/Users/weideshun/Downloads/ll/InsecureApp`
- 测试账号：虚构 `demo` / `pass`

## 修复前（执行 4）

| 问题 | 可读 | 有安全影响 | 证据 |
|---|---|---|---|
| UserDefaults 存 password / username | 是 | 是（明文密码） | `Library/Preferences/com.weideshun.InsecureApp.plist` |
| NSLog `login password=%@` | 是（Console） | 是（日志泄露） | 过滤 `login password=` |
| `isLoggedIn` 布尔 | 是 | 是（改 true 杀进程再开仍显示已登录） | 改 plist 前后行为对照 |
| Keychain `kSecAttrAccessibleAlways` | 写入 API 已确认 | 过宽 accessibility | 本周未做导出工具验证 |

启动逻辑：`refreshStatus` 只看 defaults 的 `isLoggedIn`，等于没认证。

## 问题卡（修复前）

```text
资产：com.weideshun.InsecureApp.plist 的 password、isLoggedIn
前置条件：点 Login
复现步骤：Filza 读 plist；Logout 后把 isLoggedIn 改回 true，杀 App 再开
观察证据：plist 有明文 pass；改布尔后仍显示已登录
影响：有安全影响
根因：敏感数据进 UserDefaults；登录态只信本地布尔
```

```text
资产：系统日志
前置条件：点 Login
复现步骤：Console 过滤 login password=
观察证据：出现虚构密码
影响：有安全影响（日志泄露）
根因：NSLog(@"login password=%@", pass)
```

## 修复后（执行 5）

| 项 | 修复 | 回归 |
|---|---|---|
| password in defaults | 不再写入；启动 `removeObjectForKey:password` / `isLoggedIn` | plist 不再有 password |
| 日志 | `NSLog(@"login ok")` | Console 无 `login password=` |
| 登录态 | 仅内存 `sessionAuthenticated` | 杀进程必须重新输入密码；改 plist 的 isLoggedIn 无效 |
| Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | 写入 API 已收紧 |

回归由操作者确认：三项都对。

## 修复建议（练习结论）

- 密码不要进 UserDefaults / Documents plist
- 不要用 `isLoggedIn` 单独作为认证
- 日志不要打印密码
- Keychain 用 `WhenUnlockedThisDeviceOnly` 一类更严的 accessibility
- 测试只用虚构账号
