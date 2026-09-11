# W11 签名混淆

## 环境

- 日期：2026-09-11
- App：`com.weideshun.SignDemo`（W11 混淆版）
- 后端 secret 未改：仍是 `local-demo-secret-v1`
- HMAC：仍是 SHA256，canonical 未改
- 新 Mach-O：`artifacts/SignDemo-w11`

## 原理（简单说）

签名还是：

```text
sign = HMAC-SHA256(secret, "user_id=" + user_id + "&timestamp=" + ts + "&nonce=" + nonce + "&action=" + action)
```

W10 之前 `secret` 以字符串字面量躺在二进制里，`strings | grep local-demo-secret-v1` 一次命中。

W11 不改算法，只改 **secret 怎么存放**：

1. 把明文 UTF-8 拆成两段，各 10 字节：`local-demo` 和 `-secret-v1`。
2. **XOR**：每个字节和固定值 `0x5A` 做异或。`A XOR K XOR K = A`，所以再用一次 `0x5A` 就能还原。
3. App 里只存 XOR 后的数组 `kPartA` / `kPartB`。
4. 运行时 `+[SecretStore obfuscatedSecret]` 循环：`byte[i] = part[i] XOR 0x5A`，拼成 20 字节字符串，仍是 `local-demo-secret-v1`。
5. `HMACSigner` 照旧吃这个 NSString，调用 `CCHmac`。

这叫混淆，不是加密：XOR 密钥就在旁边的 `mov w9,#0x5a` 里，Ghidra 一眼能看到。目的是让 **strings 不再（只靠）整串明文** 定位 secret，逼你跟还原函数和 HMAC 调用。

页面上的 **明文 secret（对比）** 开关默认关。打开则走旧字面量 `SignDemoSigningSecret`，方便和 XOR 路径对比。因为这个字面量还编译进包，所以 `strings SignDemo-w11` **仍然能搜到** `local-demo-secret-v1`。这不是还原失败，而是 Debug 开关把明文又放回去了。运算在开关关闭时并不依赖这整串字面量。

## 改造前 strings

```text
strings artifacts/SignDemo | grep local-demo-secret-v1
→ local-demo-secret-v1
```

基线 Login（明文脚本）：

```text
timestamp=1789100038 nonce=0e4761a1ab253761
sign=21b36bab8fd5c73dd8a5c458846067d4f966d156deeea014a3bbc317e5c5b006
HTTP 200
```

## 混淆规则

| 项 | 值 |
|---|---|
| XOR | `0x5A` |
| part A（密文 hex） | `3635393b36773e3f3735`（10 字节） |
| part B（密文 hex） | `77293f39283f2e772c6b`（10 字节） |
| 还原后 | `local-demo-secret-v1` |
| 类 | `SecretStore` |
| HMAC | 仍在 `HMACSigner` |

Ghidra：`+[SecretStore obfuscatedSecret]` 里两段循环，`subs ...,#0xa` 各 10 次，`mov w9,#0x5a` + `eor`，最后 `mov x3,#0x14`（20 字节）交给 `NSString`。XREF 来自 `currentSecret`。

## 开关行为

| 明文 secret | 路径 | Login |
|---|---|---|
| 关（默认） | XOR 还原 | 200 |
| 开 | 字面量 `SignDemoSigningSecret` | 200 |

两边最终 secret 相同，所以 sign 规则相同。

## Frida 一次请求（开关关）

```text
message (canonical) = user_id=demo-user-001&timestamp=1789103090&nonce=c07afcbfdb7942af&action=login
secret              = local-demo-secret-v1
digest (sign)       = ed50341d62bc8783a89ffc0503dcec23faef5de0dd8deb609d459e4a4ce116b3
```

运行时已经还原成功。脚本：`scripts/frida/capture_hmac_input.js`。

## Ghidra 还原函数

- 函数：`+[SecretStore obfuscatedSecret]`
- XOR 立即数：`0x5a`（反汇编出现两次，对应两段）
- HMAC 附近：`+[HMACSigner hexHMACSHA256WithMessage:secret:]` 仍调 `CCHmac`

## sign_v2.py

`scripts/reproduce/sign_v2.py`：同样 XOR 还原，再 HMAC。

- `--verify-frida`：与上面 `ed50341d...` 完全一致
- 默认 Login：HTTP 200

没有「直接写死明文却假装混淆」；明文只作为还原后的断言。

## 和 W10 对照

| | W10 | W11 |
|---|---|---|
| strings 整串 secret | 直接命中 | 仍可能命中（开关字面量还在） |
| 定位重点 | `HMACSigner` 符号 | 先找到 `SecretStore` 还原，再跟 HMAC |
| 算法 | HMAC-SHA256 | 没变 |
| 后端 | 同一 secret | 没改 |

strings 变难（至少运算路径不靠整串）并不等于换了签名算法。Ghidra 伪代码里的 `eor` / `0x5a` 要用 Frida 打印的 secret 验证。

## 产物

```text
SignDemo/SecretStore.m
scripts/frida/capture_hmac_input.js
scripts/reproduce/sign_v2.py
notes/week-11-signature-location.md
```

## 下一步

进入 [`iOS逆向实施步骤/12-W12-M2签名逆向综合-详细执行步骤.md`](../iOS逆向实施步骤/12-W12-M2签名逆向综合-详细执行步骤.md)。不要上更重的保护。
