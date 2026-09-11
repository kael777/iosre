# W10 脱壳概念与静态动态

## 环境

- 日期：2026-09-11
- 设备：iPhone XR / iOS 18.5 / Dopamine rootless / Frida 17.17.0
- 自建包：SignDemo（`cryptid 0`）、UnCrackable L1（`cryptid 0`）
- **未**对商店生产 App 跑 dump

## FairPlay / cryptid

**FairPlay**：商店 App 磁盘上有一段代码加密（`LC_ENCRYPTION_INFO_64` 里 `cryptid 1`）。进程加载并过 DRM 后，内存里才是明文。直接拿商店主文件进 Ghidra，`__TEXT` 往往不可读。

**脱壳**：从已经解密的进程内存写出 Mach-O。只允许对自己有权分析的包做。

| cryptid | 含义 |
|---|---|
| 0 | 未加密。Xcode 开发包常态。不是「已经脱壳」。 |
| 1 | FairPlay 加密段。静态分析前才需要 dump。 |

`cryptoff` / `cryptsize` 只是区间位置和长度，还要看 cryptid。

## 自建包实测

**SignDemo** `artifacts/SignDemo`：

```text
cmd LC_ENCRYPTION_INFO_64
cryptoff 16384  cryptsize 81920  cryptid 0
```

**UnCrackable L1** `artifacts/UnCrackableL1`：

```text
Mach-O 64-bit executable arm64
cryptid 0  cryptsize 49152
nm: _do_it  @ 0x10000b9d8  (__TEXT,__text) external
```

两份都是自己编译的 arm64，都是 0。说明这是开发包常态，不是 SignDemo 特例。

## 为什么这不能代表商店脱壳

1. 商店包常见 `cryptid 1`，磁盘上代码不可读；练习包磁盘上已经可读。
2. 对 SignDemo dump，内存和 `artifacts/SignDemo` 几乎同类，学不到「解密后再转储」。
3. dump 工具还要过越狱类型、Frida 版本、SSH；练习包过了这一关，也不等于会了 FairPlay。

## dump 工具 README 摘录（未用于第三方）

| 仓库 | README |
|---|---|
| AloneMonkey/frida-ios-dump | 经典原版，约 2023-05 后停更。越狱 + Frida + `iproxy` SSH。未提 iOS 18 / Dopamine / Frida 17。 |
| incogbyte/frida-ios-dump-ng | 2026-09 仍更新。写明 Frida 17+、越狱。未提 iOS 18 / Dopamine / rootless。 |
| ddddhm1234/frida-17-ios-dump | 适配 Frida 17 已删 API。需 SSH。未提 iOS 18 / Dopamine。 |

本机组合 **iOS 18.5 + Dopamine rootless + Frida 17.17** 没有任何一份 README 宣称覆盖。本周结论：**不跑 dump**。未对微信/银行/商店 App 使用。

## HMACSigner 对照表

见 [`reports/signdemo-static-dynamic.md`](../reports/signdemo-static-dynamic.md)。

Frida 实测（点 Login）：

```text
+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]
userID=demo-user-001 timestamp=0x6aa37db4
canonical=user_id=demo-user-001&timestamp=1789099444&nonce=8d21d3767ee87462&action=login
```

`0x6aa37db4` = 十进制 `1789099444`，是整数，不是指针。

## Ghidra 一处已用 Frida 修正的推断

Ghidra 常把 timestamp 显示成 `undefined8` 或像指针。源码是 `long long`，格式串是 `%lld`，Frida canonical 里是十进制整数。以源码 + Frida 为准。伪代码不是原始源码。

PIE：nm/Ghidra 的 `0x100008064` 是文件未加载地址，不必等于运行时绝对地址。对 **符号名**。

## 下一步

进入 [`iOS逆向实施步骤/11-W11-签名混淆-详细执行步骤.md`](../iOS逆向实施步骤/11-W11-签名混淆-详细执行步骤.md)。W10 不要改 secret。
