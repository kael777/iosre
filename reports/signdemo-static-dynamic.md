# SignDemo 静态 ↔ 动态对照（HMACSigner）

## 对象

- 静态：`artifacts/SignDemo` + Ghidra `SignDemo-W9`（AARCH64）
- 动态：`frida -U -n SignDemo -l scripts/frida/hook_network_request.js`，点 Login
- 源码：`HMACSigner.m`、`APIConfig.m`
- 练习 secret：`local-demo-secret-v1`（明文，不是真实业务密钥）

## 对照表

| 项 | 静态（nm / Ghidra） | 动态（Frida） | 源码 |
|---|---|---|---|
| 类 | `HMACSigner`、`_OBJC_CLASS_$_HMACSigner` | `ObjC.classes.HMACSigner` | `HMACSigner.m` |
| newNonce | `+[HMACSigner newNonce]` @ 文件 `0x10000850c` `__TEXT,__text` | `[+] +[HMACSigner newNonce]`，Login/Order 进入 | `+ newNonce` |
| canonical 方法 | `+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]` @ `0x100008064` | 同类方法；返回完整 canonical | 同名类方法 |
| canonical 格式 | strings：`user_id=%@&timestamp=%lld&nonce=%@&action=%@` | `user_id=demo-user-001&timestamp=1789099444&nonce=8d21d3767ee87462&action=login` | 按该顺序拼接 |
| sign | `+[HMACSigner signWithUserID:timestamp:nonce:action:secret:]` @ `0x1000083e4` | 返回 64 位小写 hex | `CCHmac` SHA256 |
| hex 实现 | `+[HMACSigner hexHMACSHA256WithMessage:secret:]` @ `0x1000081e4` | 被 sign 调用 | `CCHmac` |
| secret | strings：`local-demo-secret-v1` | 第一阶段硬编码常量 | `APIConfig.m` `SignDemoSigningSecret` |
| timestamp 类型 | Ghidra 常显示 `undefined8` / 像指针 | 寄存器 `0x6aa37db4` = 十进制 `1789099444`，写入 canonical 的是整数 | `long long` |

## 一次 Login 的动态记录

```text
+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]
    实例/类方法：类方法
    userID=demo-user-001 timestamp=0x6aa37db4
    nonce=8d21d3767ee87462 action=login
    返回值 canonical = user_id=demo-user-001&timestamp=1789099444&nonce=8d21d3767ee87462&action=login
```

静态 Symbol Table 里点开的就是这个 `+ canonicalString...`。名字对得上；PIE 下绝对地址不必相等。

## 闭环

```text
strings / nm 初筛
→ Ghidra 字符串 xref + Symbol Table
→ Frida Hook 同类方法
→ 发现 timestamp 伪代码类型不可信
→ 以 Frida + %lld + 源码修正
```

## 伪代码不是源码

不要把 Decompile 窗口当成 `HMACSigner.m`。可信的是：方法名、明文字符串、能对上的调用关系。不可全信的是：寄存器类型、是否对象、是否内联。本周用 Frida 修正的就是 timestamp。

## 和脱壳的关系

本表能直接填，是因为 SignDemo **`cryptid 0`**，磁盘上就是明文。商店 `cryptid 1` 的包在 dump 之前，这张表的「静态」列往往填不出函数名。自建未加密 App **不能**代表商店脱壳过程。

## 未做

- 未 dump 商店 App。
- 未对 SignDemo 跑 dump（无教学收益）。
- 未改 secret（W11）。
