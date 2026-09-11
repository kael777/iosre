# SignDemo 静态定位（签名流程）

## 对象

- 二进制：`/Users/weideshun/Downloads/ll/artifacts/SignDemo`
- 架构：AARCH64 / ARM64，MH_MAGIC_64，iphoneos
- 对照源码：`SignDemo/HMACSigner.m`
- 对照动态：W7 Frida `hook_network_request.js`

练习 secret `local-demo-secret-v1` 可写在本报告中（第一阶段刻意明文）。不是真实业务密钥。

## 字符串 → 函数

| 字符串（strings / Ghidra Defined Strings） | 含义 | 静态上应落到 |
|---|---|---|
| `local-demo-secret-v1` | HMAC 密钥 | `hexHMACSHA256WithMessage:secret:` / `signWithUserID:...secret:` |
| `user_id=%@&timestamp=%lld&nonce=%@&action=%@` | canonical 格式 | `+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]` |
| selector 名 `newNonce` 等 | ObjC 方法名 | 同名 `+` 方法 |

Ghidra：**Search → For Strings** 搜上述字 → **XRefs** 跳到引用。**Symbol Table** 过滤 `HMACSigner` 可直接打开四个类方法。

## 符号（nm 实测）

均在 `__TEXT,__text`：

```text
+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]
+[HMACSigner hexHMACSHA256WithMessage:secret:]
+[HMACSigner signWithUserID:timestamp:nonce:action:secret:]
+[HMACSigner newNonce]
```

另有 `_OBJC_CLASS_$_HMACSigner`（`__DATA,__objc_data`）和 `_objc_msgSend$newNonce` 等 stub，说明有调用方（`APIClient` 的 `signedBodyForAction:userID:`）。

## 和源码 / Frida 对照

| 来源 | 结论 |
|---|---|
| `HMACSigner.m` | timestamp 是 `long long`；canonical 按固定顺序拼接 |
| strings `%lld` | 格式化时把 timestamp 当整数 |
| W7 Frida | 返回值 `user_id=...&timestamp=...&nonce=...&action=login` |
| Ghidra | 能找到同一函数和同一字符串；Decompile 的参数类型是猜测 |

## 一处必须动态验证的推断

Ghidra 伪代码经常把 `canonicalString...` 的 timestamp 显示成 `undefined8` 或「像指针」。

**不要**据此认为运行时传入的是 `NSNumber *` 或对象。已经用源码和 Frida 验证：它是整数。伪代码不是原始源码。

Ghidra 适合回答「这个字符串在哪个函数里」。参数到底是什么，以源码和 Frida 为准。

## 未做

- 未把 Ghidra 工程入库。
- 未分析商店 App（`cryptid` 仍为 0，W10 再对比）。
- 未把 Swift 修饰名当主线（本包签名路径是 ObjC）。
