# 2026 Q1 复盘（M0–M3）

- 日期：2026-09-12
- 对应：本仓库 W1–W20 / [`iOS逆向_2026Q1完整实施计划.md`](../iOS逆向_2026Q1完整实施计划.md)
- Q2 计划：[`iOS逆向_2026Q2完整实施计划.md`](../iOS逆向_2026Q2完整实施计划.md)
- 环境：Mac mini M2 + iPhone XR iOS 18.5 Dopamine + 自建 SignDemo / InsecureApp / 本机 Flask
- 授权边界：自己的设备、自己的 App、OWASP UnCrackable、DVIA。不含商店第三方、不含生产用户数据。

## 1. M0–M3

| 里程碑 | 状态 | 依据 |
|---|---|---|
| M0 环境可用 | 通过 | Frida USB、Xcode 26.6、mitmproxy、Ghidra、越狱 XR |
| M1 SignDemo 综合 | 通过 | W6：流量、Pinning、协议可见性 |
| M2 签名逆向 | 通过 | `reports/signature-reproduction.md` |
| M3 漏洞研究入门 | 通过 | 报告、后端、脚本、W20 闭环 |

M3 产物对照：

- 漏洞/缺陷报告（≥3）：`reports/local-api-replay.md`、`local-api-idor.md`、`insecureapp-storage.md`
- 签名报告：`reports/signature-reproduction.md`
- 可重复后端：`SignDemo/backend`，pytest 13 passed，`replay_local_request.py --mode secure` ALL PASS
- 可复用脚本：`scripts/frida/*.js`、`scripts/reproduce/*.py`（超过 5 个）
- 闭环：`frida-ps -U`、本机重放 ALL PASS、W19 `frida -U -n SignDemo` attach 观察 JailbreakCheck
- DVIA / UnCrackable 只是授权靶场，不算「发现了某公司的漏洞」

## 2. 能独立执行的命令

```text
frida-ps -U
frida -U -n SignDemo
cd Desktop/SignDemo/backend && .venv/bin/python3 -m pytest -q
.venv/bin/python3 ../scripts/reproduce/replay_local_request.py --mode secure
.venv/bin/python3 ../scripts/reproduce/idor_local_request.py --mode secure
```

真机 URL 用局域网 IP `:5443`，不用 `127.0.0.1`。

## 3. 仍需查资料的工具

- Frida 17：无 `Module.findExportByName`
- Ghidra AARCH64 类型显示
- Theos rootless / nic.pl
- 旧工程 `libarclite`
- 商店 IPA `cryptid=1` vs 自编译 `cryptid=0`

## 4. 可快速定位的失败

| 现象 | 先查 |
|---|---|
| 真机连不上后端 | 是不是 `127.0.0.1` |
| mitm 证书错误 | Pinning / ATS / 上游 CA |
| IDOR 仍 200 | 是否旧 `app.py`、ACL 没加载 |
| 越狱检测全 NO | 是否只查了 Cydia（Dopamine 要 `/var/jb`） |
| 免费账号装不上 | 3 App 上限 |
| 界面没有 `P_TRACED=` | 底部输出框，开关关再开 |

## 5. 只在自建环境成立的结论

- HMAC secret、Pinning 哈希、虚构用户只属于 SignDemo。
- `cryptid=0` ≠ 商店包已脱壳。
- 重放/IDOR 对照只打了本机后端。
- XOR / 越狱检测 / **客户端机器指纹** 提高静态或伪造成本，挡不住 hook 和协议层改字段。
- 客户端被绕过 ≠ 服务端被打穿。

## 6. 下一季度

选 **应用安全审计**，对象改为公司 IM 测试包。细节见 [`iOS逆向_2026Q2完整实施计划.md`](../iOS逆向_2026Q2完整实施计划.md)。
