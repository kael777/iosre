# W7 Frida ObjC Runtime

## 环境

- 日期：2026-09-11
- 设备：iPhone XR / iOS 18.5 / arm64e / Dopamine
- App：`com.weideshun.SignDemo`
- Frida：17.17.0
- 反调试：关闭
- 优先 attach：`frida -U -n SignDemo`

虚构测试账号：`demo-user-001` / `demo-password`。

## 找到的类

`list_runtime_methods.js` 查找：

```text
ViewController
HMACSigner
APIClient
APIResponse
PinningURLSessionDelegate
AntiDebug
APIConfig
```

`ObjC.available = true`。`ObjC.choose(ViewController)` 在主界面可见时能拿到活实例。`HMACSigner` 的签名方法全是 **类方法**（`+`）。

## 实例方法 vs 类方法（各举一例）

| 种类 | 例子 | 触发 |
|---|---|---|
| 实例方法 `-` | `-[ViewController loginButtonTapped:]` | 点 Login |
| 实例方法 `-` | `-[APIClient loginWithUserID:password:completion:]` | Login 发请求 |
| 类方法 `+` | `+[HMACSigner newNonce]` | Login / Order 组签名 |
| 类方法 `+` | `+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]` | 拼 canonical |
| 类方法 `+` | `+[HMACSigner signWithUserID:timestamp:nonce:action:secret:]` | 算 HMAC |

Frida 里写成 `ObjC.classes.HMACSigner["+ newNonce"]`，不要写成 `-`。

调用约定：`args[0]=self`，`args[1]=_cmd`，从 `args[2]` 起是参数。`timestamp` 是 `long long`，不能 `ObjC.Object`。

## Hook 记录

观察脚本：`scripts/frida/hook_network_request.js`（只读，无 `replace`）。

| 目标方法 | 输入 | 输出 | 是否改行为 |
|---|---|---|---|
| `- viewDidLoad` | self | 无业务返回 | 否 |
| `- loginButtonTapped:` | sender | 无 | 否 |
| `- loginWithUserID:password:completion:` | userID、password；**不包装** args[4] block | 无 | 否 |
| `+ newNonce` | 无 | NSString nonce | 观察脚本否 |
| `+ canonicalString...` | userID / timestamp / nonce / action | canonical NSString | 否 |
| `+ signWithUserID...` | 同上 + secret | 64 位 hex | 否 |

点 Login 可见：

```text
userID = demo-user-001
canonical = user_id=demo-user-001&timestamp=...&nonce=...&action=login
sign = <64 hex>
```

与 `scripts/reproduce/sign_login.py` 的拼法一致。`args[4]` completion block 未包装。

## 打印过的 NSString / NSDictionary

- NSString：`userID`、`password`（虚构）、`nonce`、`canonical`、`sign`
- NSDictionary：本周未单独 Hook 字典对象；login 的 JSON 仍在 App 文本区可见
- NSData：未 Hook

## 改返回值实验与恢复

脚本：`scripts/frida/replace_newNonce.js`（不要和观察脚本当默认混用）

第一版 `stringWithString_` + `retval.replace(ObjC.Object)`：**第一次 Login 闪退**，`Connection terminated`。

第二版 `alloc/init` + `retain` + `retval.replace(.handle)`：不再闪退。实测三次：

```text
原返回值 = 78f5bfbaad97ca8f  →  frida-fixed-nonce
原返回值 = 1810a6cd9d34797e  →  frida-fixed-nonce
原返回值 = d1b963f1e9af86c3  →  frida-fixed-nonce
```

固定 nonce 后：第一次 Login 应 200，之后同一 nonce 应 409。Frida `exit` 后再 Login，nonce 恢复随机，应 200。

## Hook 导致闪退的两个原因

都是自己踩过的，不是网上抄的：

1. **spawn / 属性 Hook 时机不对**（W4 bypass）：脚本加载阶段调用 `NSBundle`，或 Hook `pinningEnabled` 的 getter/setter。`viewDidLoad` 一赋值进程就没了，表现为 `Failed to load script: the connection is closed`。
2. **改返回值生命周期不对**（W7 执行 6 第一版）：`stringWithString_` 是 autorelease，`replace` 需要稳定的 `NativePointer`。原方法一返回对象就被释放，Login 用野指针闪退。正确做法是 `alloc/init`、`retain`、`.handle`。

另外不要包装 `completionHandler`，也不要把 JS `null` 传给 `setLastFailureReason_`。

## 产物

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/list_runtime_methods.js
/Users/weideshun/Desktop/SignDemo/scripts/frida/hook_network_request.js
/Users/weideshun/Desktop/SignDemo/scripts/frida/replace_newNonce.js
/Users/weideshun/Downloads/ll/notes/week-07-frida-runtime.md
```

## 未验证项

- 未批量 Hook 系统类。
- 未改 `sign` 或 Pinning 返回值。
- 未对 UnCrackable `do_it` 改返回值（那是 W8）。

## 下一步

进入 [`iOS逆向实施步骤/08-W8-Native-Hook-UnCrackable-L1-详细执行步骤.md`](../iOS逆向实施步骤/08-W8-Native-Hook-UnCrackable-L1-详细执行步骤.md)。观察脚本保持只读；改返回值只在单独脚本里做。
