# SignDemo 反调试 / 越狱检测实验（W19）

## 1. 对象和范围

- 日期：2026-09-12
- App：自己编写的 `com.weideshun.SignDemo`
- 设备：iPhone XR / iOS 18.5 / Dopamine **rootless**
- 脚本：`scripts/frida/observe_jailbreak_checks.js`（只 hook、不改返回值、不 exit）
- **没有** 对商店 App 做检测绕过，**没有** `ptrace(PT_DENY_ATTACH)` / `exit`

检测命中只说明「这段客户端逻辑认为环境异常」。它 **不能** 代替 W17 HMAC 和 W18 对象级 ACL。

## 2. 三层不要混

| 层 | SignDemo 里的位置 | 说明 |
|---|---|---|
| **代码签名** | 免费开发证书安装；W9 `cryptid=0` | 谁签了二进制。能装上 ≠ 没被调试。 |
| **反调试** | `AntiDebug.m`：`sysctl` 看 `P_TRACED`；`isatty` | 现在有没有调试器。主屏幕 `P_TRACED=NO`，Xcode Run 常 `YES`。 |
| **越狱检测** | `JailbreakCheck.m`：路径 / URL Scheme / dylib | 环境有没有被改。和 `P_TRACED` 不是一回事。 |

`P_TRACED=YES` 不是「签名坏了」。免费证书能装也不是「没被调试」。

本周 **没有** 默认打开 `ptrace`：它和 `sysctl` 同属反调试层，打开后 Xcode / Frida 容易挂不上。

## 3. 三类越狱检测面（本机结果）

按钮 **Jailbreak Check (W19)** 只打日志，不禁用 Login。

| 面 | 查什么 | 这台 XR |
|---|---|---|
| 文件路径 | 经典 Cydia vs rootless `/var/jb` | 见下表 |
| URL Scheme | `cydia://` `sileo://` `filza://`（已登记 `LSApplicationQueriesSchemes`） | |
| 动态库 / 环境变量 | `DYLD_INSERT_LIBRARIES`、镜像名含 frida / ellekit / TweakInject / substrate | |

### 误报 / 漏报（Dopamine，不要套 Cydia 教程）

| 检测 | 结果 | 判定 |
|---|---|---|
| `/Applications/Cydia.app` | NO | **漏报**（无 Cydia） |
| `MobileSubstrate.dylib` | NO | **漏报**（经典路径） |
| `/var/jb` | YES | 命中 |
| `/var/jb/Applications/Sileo.app` | YES | 命中 |
| `/var/jb/usr/sbin/sshd` | NO | **漏报**（这台没有该文件） |
| `cydia://` | NO | **漏报** |
| `sileo://` / `filza://` | YES | 命中 |
| 镜像名含 `frida` | NO（Frida **已 attach** 仍 NO） | **漏报** |
| `ellekit` / `TweakInject` | YES | 命中（Dopamine 注入栈） |
| `DYLD_INSERT` | `systemhook.dylib` + `libViewDebuggerSupport.dylib` | `systemhook` 属越狱；ViewDebugger 来自 Xcode |
| `P_TRACED` | 主屏幕 NO；Xcode 常 YES | 反调试，不是越狱 |

只抄「有没有 Cydia.app」会把已越狱的 Dopamine 判成没越狱。  
`getppid != 1` 当越狱会误报（W6 已不当判定）。

Frida 观察时 `fileExistsAtPath:` / `canOpenURL:` 的 YES/NO 与界面一致，脚本没有改返回值、没有杀进程。

## 4. XOR 混淆（执行 4）

路径按字节 XOR `0x5A`，运行时还原再交给 `fileExistsAtPath:`。方法名仍是 `JailbreakCheck`：混淆的是 **字面量**，不是算法。

| | 混淆前 | 混淆后 |
|---|---|---|
| `strings` 里 `/var/jb`、`/Applications/Cydia` | 有 | **无**（`no plaintext paths`） |
| 运行时 `varjb` / `sileoApp` | YES | 仍 YES |
| Frida `fileExistsAtPath:] /var/jb` | YES | 仍 YES，path 已还原 |

结论：XOR 提高 `strings` / grep 成本，**不提高** 对 Frida 的抵抗。Hook `fileExistsAtPath:` 或 `+[JailbreakCheck statusSummary]` 即可，不必先把字符串搜出来。

## 5. 客户端不能替代服务端

即使把 `JailbreakCheck` hook 成全 NO：

- W17：没 sign / 错 sign / 重放 nonce，本机后端仍是 400 / 401 / 409
- W18：A 的 token 读 B 的订单，修复后仍是 403

越狱只改变 **设备上的客户端环境**。本机 API 是否放行，看的是签名和对象属主，不是 App 有没有弹「检测到越狱」。

不要写成「已越狱所以后端不安全」。也不要把绕过检测当成拿到生产数据。

## 6. 成本和收益

| 做法 | 成本 | 实际收益 |
|---|---|---|
| 明文路径 + 日志 | 低 | 能练检测面；`strings` 一眼看到 |
| XOR 路径 | 低 | 挡静态 grep；挡不住 hook |
| `ptrace` + `exit` | 高（挡自己的 Frida / Xcode） | 本周不做 |
| 服务端 HMAC + ACL | 已有 | 改客户端检测也过不了 |

测完请把 **反调试开关关掉**。Jailbreak Check 是按钮，不点就不会跑。
