# SignDemo 签名复现报告（M2）

## 1. 对象和授权范围

- 日期：2026-09-11
- App：自己编写的 `com.weideshun.SignDemo`
- 后端：本机 Flask `https://127.0.0.1:5443` / 真机 `https://192.168.1.8:5443`
- 分析者有源码和本机后端的完整授权
- **不包含** 任何第三方、商店或生产 App

测试账号为虚构：`demo-user-001` / `demo-password`。下文 token 均为练习签发值。

## 2. 接口和样本

| 接口 | 方法 | 签名 | 备注 |
|---|---|---|---|
| `/api/login` | POST JSON | 是，`action=login` | 另带 `password`，不进 canonical |
| `/api/order` | POST JSON | 是，`action=order` | 另带 `order_id`、`amount`，不进 canonical |
| `/api/health` | GET | 否 | |
| `/api/profile/<user_id>` | GET | 否 | |
| `/ws/events` | WebSocket | 否 | token 查询参数 |

本报告只复现 **login / order** 的 HMAC。

## 3. 观察到的输入输出

明文 secret 开关 **关闭**（XOR 还原路径）。Frida Hook `+[HMACSigner hexHMACSHA256WithMessage:secret:]`。

**login**

```text
canonical = user_id=demo-user-001&timestamp=1789104979&nonce=6326a68ba2771970&action=login
secret    = local-demo-secret-v1
sign      = fbbb5d8ea2f97df8863d7ee299e03e6943404de7b192afd92e9738a3de9a42fd
HTTP      = 200
```

**order**

```text
canonical = user_id=demo-user-001&timestamp=1789105003&nonce=a7c04822a8ce690d&action=order
secret    = local-demo-secret-v1
sign      = c75c9a021f747dcab12b037eb3aa2f759c88909a0c08f71b9fd286b7bdbcb19f
HTTP      = 200
```

运行时 secret 与后端配置相同。XOR 只影响存放，不影响最终 HMAC 输入。

## 4. 静态定位过程

对 `artifacts/SignDemo-w11`（AARCH64）Ghidra：

1. Symbol Table 过滤 `SecretStore` → `+[SecretStore obfuscatedSecret]`、`currentSecret`
2. 反汇编见两段 10 字节循环：`ldrb` 密文，`mov w9,#0x5a`，`eor`
3. Symbol Table 过滤 `HMACSigner` → `canonicalString...` / `hexHMACSHA256...` / `signWithUserID...` / `newNonce`
4. Strings 仍可能出现 `local-demo-secret-v1`：页面「明文 secret」开关把对比字面量留在包里，不是 XOR 失败

入口：**先还原（SecretStore），再 HMAC（HMACSigner）**。算法没有换成别的。

## 5. 动态 Hook 过程

调用链：

```text
ViewController loginButtonTapped: / orderButtonTapped:
  → APIClient loginWithUserID:password:completion: 或 createTestOrder...
      → signedBodyForAction:userID:
          → HMACSigner newNonce
          → SecretStore currentSecret
              → 关：obfuscatedSecret（分段 XOR 0x5A）
              → 开：SignDemoSigningSecret 字面量
          → HMACSigner signWithUserID:timestamp:nonce:action:secret:
              → canonicalStringWithUserID:...
              → hexHMACSHA256WithMessage:secret:   （CCHmac）
      → POST JSON
```

脚本：`SignDemo/scripts/frida/capture_hmac_input.js`（只读，不改返回值）。  
一次请求同时看到 canonical、secret、digest。

## 6. canonical 规则

```text
canonical =
    "user_id=" + user_id
    + "&timestamp=" + timestamp
    + "&nonce=" + nonce
    + "&action=" + action
```

- 顺序固定，UTF-8
- `action` 仅为 `login` 或 `order`
- `password`、`order_id`、`amount` **不进入** canonical（练习刻意留下的缺口）

## 7. HMAC 或其他算法

```text
sign = HMAC-SHA256(secret, canonical)
```

- 输出小写十六进制，64 字符
- secret 运行时为 `local-demo-secret-v1`
- 客户端存放：两段密文 XOR `0x5A`（`kPartA` / `kPartB`），不是换哈希算法

Python 对第 3 节 login 样本重算，sign 与 Frida 一致。

## 8. nonce 和时间窗口

- `timestamp`：Unix 秒，与服务器相差超过 **300 秒** → HTTP 401 `request timestamp is outside the allowed window`
- `nonce`：进程内成功用过一次 → HTTP 409 `nonce has already been used`；重启后端会清空
- 错误 `sign` → HTTP 401 `invalid signature`

`signature_v2.py --bad-timestamp` → 401；`--reuse-nonce` → 第二次 409。

## 9. 离线复现脚本

```text
SignDemo/scripts/reproduce/signature_v2.py
```

别人只需报告 + 本机后端 + 该脚本：

```bash
cd /Users/weideshun/Desktop/SignDemo
./backend/.venv/bin/python3 scripts/reproduce/signature_v2.py
./backend/.venv/bin/python3 scripts/reproduce/signature_v2.py --action order
./backend/.venv/bin/python3 scripts/reproduce/signature_v2.py --bad-timestamp
./backend/.venv/bin/python3 scripts/reproduce/signature_v2.py --reuse-nonce
./backend/.venv/bin/python3 scripts/reproduce/signature_v2.py --verify-sample
```

只连接 `127.0.0.1` 或局域网 IP。XOR 还原后断言等于 `local-demo-secret-v1`，再 HMAC。实测：login/order 200，坏 timestamp 401，重放 nonce 409。

## 10. 服务器侧修复建议

仅针对这份 **练习后端**，不是通用攻击说明：

- 不要把 HMAC secret 放在客户端（XOR 可被 Ghidra 还原）
- 继续保留时间窗和 nonce 防重放
- 把 `order_id`、`amount` 纳入 canonical，避免只改金额仍能过签
- 发布路径不要带「明文 secret」对比开关
- 继续提供 HTTPS；Pinning 可开
- 练习 CA 私钥不要进 git（仓库已忽略 `*.key`）

## 11. 限制和未验证项

- 只覆盖自建 SignDemo 与本机后端
- 未验证密钥轮换、HSM、多设备时钟
- 未分析商店 FairPlay 包（`cryptid 0` 的自建包不能代表脱壳）
- Profile / health / WebSocket 无此 HMAC
- 未把 gRPC 纳入本签名
- 虚构 token 仅用于练习，不是真实凭据
