# W14 Theos

## 环境

- 日期：2026-09-11
- 设备：iPhone XR / iOS 18.5 / Dopamine rootless
- 对象：只 Hook `com.weideshun.SignDemo`
- Theos：`/Users/weideshun/theos`（submodule 需 checkout 后 `nic.pl` 才可用）

## Theos / rootless

- `THEOS_PACKAGE_SCHEME = rootless`
- `ARCHS = arm64`
- `TARGET := iphone:clang:latest:15.0`（NIC 默认 7.0 已改掉）
- 包架构：`iphoneos-arm64`

`nic.pl` 的 `bin/nic.pl` 曾是坏符号链接（vendor submodule 空）。在 `$THEOS` 目录里跑 nic 会被拒绝，要在 `ll` 下创建工程。

## Filter / 安装后杀谁

```text
Filter Bundles = com.weideshun.SignDemo
INSTALL_TARGET_PROCESSES = SignDemo
```

NIC 问 terminate upon installation 时填 **SignDemo**，不要默认 SpringBoard。那是进程名，不是 Bundle ID。

## 日志

安装后划掉 SignDemo 再开即可，不必 respring。

```text
[SignDemoTweak] viewDidLoad self=<ViewController: 0x101c70000>
[SignDemoTweak] loginButtonTapped: sender=<UIButton: ...>
```

均 `%orig`，Login 仍 200。

## deb

```text
packages/com.weideshun.signdemotweak_0.0.1-1+debug_iphoneos-arm64.deb
```

Sileo：隔空投送 → 文件 App → 用 Sileo 打开 → 安装。

## 卸载

Sileo 已安装里 Remove。划掉 SignDemo 再开，Console 过滤 `SignDemoTweak`：**没有日志**。App 行为恢复。

## 未做

未 Hook SpringBoard；未改签名返回值。

## 下一步

进入 [`iOS逆向实施步骤/15-W15-DVIA-客户端存储-详细执行步骤.md`](../iOS逆向实施步骤/15-W15-DVIA-客户端存储-详细执行步骤.md)。仍限定授权靶场和自建 App。
