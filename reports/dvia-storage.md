# DVIA-v2 客户端存储

## 环境

- 日期：2026-09-11
- 设备：iPhone XR / iOS 18.5 / Dopamine
- App：DVIA-v2，Bundle ID `com.weideshun.dviav2`
- 安装：源码 + 免费证书（已去掉 Flurry；Pods Deployment Target 15.0）
- 测试值：虚构 `demo` / `pass` / `demo-secret-001`

## 可读 vs 安全影响

| 问题 | 可读 | 有安全影响 |
|---|---|---|
| UserDefaults `DemoValue` | 是 | 把敏感串当普通偏好存，备份/越狱可读 |
| Documents `userInfo.plist` 明文密码 | 是 | 明文账号密码落盘，影响更高 |

DVIA 当对照靶场，本周未改 DVIA 源码。

## 问题卡 1：NSUserDefaults

```text
资产：Library/Preferences/com.weideshun.dviav2.plist 键 DemoValue
前置条件：Local Data Storage → UserDefaults
复现步骤：输入虚构 demo-secret-001，点保存
观察证据：Filza 打开上述 plist，键 DemoValue 为测试串
影响：可读；敏感数据等同普通配置
根因：UserDefaults.standard.set(..., forKey: "DemoValue")
修复建议：敏感数据不要进 UserDefaults；用 Keychain 并收紧 accessibility
修复后回归结果：本周不改 DVIA
```

## 问题卡 2：Plist 明文密码

```text
资产：Documents/userInfo.plist 的 username / password
前置条件：Local Data Storage → Plist
复现步骤：username=demo password=pass，点保存
观察证据：Filza 打开 Documents/userInfo.plist，明文键值
影响：有安全影响（明文密码在 Documents）
根因：NSMutableDictionary writeToFile userInfo.plist
修复建议：禁止把密码写入 Documents plist
修复后回归结果：本周不改 DVIA
```

## 沙盒路径

相对容器：

```text
Library/Preferences/com.weideshun.dviav2.plist
Documents/userInfo.plist
```

绝对路径带每次安装变化的 UUID：

```text
/var/mobile/Containers/Data/Application/<UUID>/...
```
