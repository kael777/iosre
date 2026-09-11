# W12 SignDemo M2

## 环境

- 日期：2026-09-11
- 对象：仅 `com.weideshun.SignDemo` + 本机后端
- 混淆：XOR `0x5A`，HMAC-SHA256 未改

## 本周怎么复查

1. 源码跟调用链：`loginButtonTapped:` → `APIClient` → `SecretStore` → `HMACSigner` → POST
2. 新抓样本（不用 W11 旧 timestamp）：login `1789104979` / order `1789105003`
3. Ghidra 再确认 `obfuscatedSecret` 的 `mov w9,#0x5a` + `eor`；HMAC 仍在 `HMACSigner`
4. Frida `capture_hmac_input.js`：运行时 secret 仍是 `local-demo-secret-v1`
5. `signature_v2.py`：200 / 401 / 409

## 脚本与报告

```text
scripts/reproduce/signature_v2.py
reports/signature-reproduction.md
```

## M2 清单

- [x] 不看旧脚本也能重新定位签名入口
- [x] 能解释一次请求从按钮到网络发送的调用链
- [x] 能用离线脚本得到服务端接受的结果
- [x] 改动时间戳或 nonce 后服务端能拒绝
- [x] 报告只涉及自己的 App 和后端

## 下一步

进入 [`iOS逆向实施步骤/13-W13-LLDB-断点-详细执行步骤.md`](../iOS逆向实施步骤/13-W13-LLDB-断点-详细执行步骤.md)。先用 Xcode 对本机 SignDemo 下源码断点，不要急着配越狱 debugserver。
