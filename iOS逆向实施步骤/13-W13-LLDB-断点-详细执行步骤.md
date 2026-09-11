# W13 LLDB 与断点：详细执行步骤

> 本文件是 [`iOS逆向_2026完整实施计划.md`](../iOS逆向_2026完整实施计划.md) 中“17. W13：LLDB、断点和崩溃定位”的执行手册。  
> 对象：自己的 SignDemo。用 **Xcode 调试器** 连 XR。  
> 本周 **先不要** 配越狱 debugserver。Dopamine rootless 下路径和 entitlement 常变，不确定的旧命令不要当固定步骤。

---

## 本周在练什么

Frida 是往进程里 **注入脚本**。LLDB 是调试器：在指定位置 **停住**，看栈、寄存器、ObjC 对象。

```text
Xcode Run（带调试器）
→ 源码断点停在某一行
→ 符号/方法断点停在 ObjC 方法入口
→ bt 看调用栈
→ register read / po 看 x0 和对象
→ 保存一次可复现崩溃的符号化记录
```

arm64 上 **`x0` 最常见的两种用途**：

| 时机 | `x0` 通常是 |
|---|---|
| 刚进入 ObjC 方法 | `self`（实例方法）或类对象（类方法） |
| 函数即将返回 / 停在 `ret` 附近 | 返回值（对象指针或整数） |

`x1` 在 ObjC 里经常是 `_cmd`（selector）。不要把每次 `x0` 都当成返回值。

---

## 当前状态

- 工程：桌面 `/Users/weideshun/Desktop/SignDemo`（日常编译仍用这份）
- 类：`ViewController`、`HMACSigner`、`SecretStore`
- 真机：XR + 免费开发证书，Xcode 已能 Run 上去

---

## 本文件完成后的结果

- 能在 `loginButtonTapped:` 和 `+[HMACSigner newNonce]` 停住
- 一份 `bt` 输出
- 能用自己的话解释 `x0`
- `reports/signdemo-crash-lldb.md`（脱敏崩溃记录）
- `notes/week-13-lldb.md`

执行顺序：

```text
执行 1  Xcode 带调试器跑 SignDemo
执行 2  源码断点
执行 3  符号/方法断点
执行 4  bt、寄存器、po
执行 5  可复现崩溃 + 符号化
执行 6  写笔记
```

---

## 执行 1：Xcode 带调试器运行

1. 打开桌面 `SignDemo.xcodeproj`。
2. 运行目标选 **iPhone XR**（不要只选 Generic iOS Device）。
3. 确认方案是 Debug。
4. `Command + R`。左下角应出现调试条（断点、继续、步过）。
5. 底部打开 **Debug area**。右边是控制台，可切到 **lldb** 提示符 `(lldb)`。

进程必须由 Xcode 拉起。只在手机上点图标打开、再 attach，本周不当主路径。

### 验收标准

- [x] Run 后调试器连上 XR 上的 SignDemo
- [x] 能看到 `(lldb)` 或调试条

---

## 执行 2：源码断点

1. 打开 `ViewController.m`，在 `loginButtonTapped:` 方法 **第一行有效代码** 左边点出蓝色断点。
2. 再打开 `HMACSigner.m`，在 `+ newNonce` 的 `return` 那一行下断点。
3. 手机上点 **Login**。
4. Xcode 应停在 `loginButtonTapped:`，绿色箭头指着当前行。
5. 点 Continue（`Control + Command + Y`），应变到 `newNonce`。

记录：先停在哪个方法、Continue 后是否进 `HMACSigner`。这就是源码级调用顺序，应和 M2 调用链一致。

### 验收标准

- [x] 能在自建 App 中停在源码断点
- [x] Login 能从 ViewController 跟到 HMACSigner

---

## 执行 3：符号 / 方法断点

源码断点依赖你有 `.m`。符号断点只靠方法名，后面看无源码的库会用到。

1. Breakpoint navigator（`Command + 8`）左下 `+` → **Symbolic Breakpoint**。
2. Symbol 填（整段复制）：

```text
+[HMACSigner hexHMACSHA256WithMessage:secret:]
```

3. 删掉或暂时关掉执行 2 的源码断点，避免一次停太多次。
4. 再点 Login。应停在该方法入口（可能停在汇编，有符号就会显示方法名）。

LLDB 里也可以：

```text
(lldb) breakpoint set -n "+[HMACSigner newNonce]"
(lldb) breakpoint list
(lldb) continue
```

实例方法用 `-`，类方法用 `+`，和 Frida 一样。

可选：再加一条 **Exception Breakpoint** → Objective-C。本周先认识，执行 5 再用。

### 验收标准

- [x] 符号断点能在 `HMACSigner` 上停下
- [x] 知道 `+` / `-` 不能写错

---

## 执行 4：栈、寄存器、`x0`

停在 `loginButtonTapped:` **入口**（方法第一行）时，在 lldb 执行：

```text
bt
register read x0 x1 x2
po $x0
```

记下：

```text
bt 最上面几帧：
x0 的 po 结果（应是 ViewController 实例）：
x1：
```

**术语**

| 命令 | 作用 |
|---|---|
| `bt` / `thread backtrace` | 当前线程调用栈。上面是叶子，下面是调用者。 |
| `register read` | 读通用寄存器。arm64 参数/返回值主要走 `x0`–`x7`。 |
| `po $x0` | 把 `x0` 当 ObjC 对象打印。不是对象时会失败或乱。 |
| `p/x $x0` | 只看十六进制，不解释成对象。 |

再 `continue` 停到 `+[HMACSigner newNonce]` **即将 return** 时：

```text
register read x0
po $x0
```

这里的 `x0` 更接近 **返回的 nonce 字符串**。对比：方法入口的 `x0` 是类对象，不是 nonce。

把这两次 `x0` 的差别写进笔记，执行 4 才算理解，而不是只复制了命令。

### 验收标准

- [x] 能查看调用栈
- [x] 能解释 `x0` 在 arm64 调用约定中的常见用途（self vs 返回值）

---

## 执行 5：可复现崩溃和符号化

目的：有一份 **自己 App** 的崩溃，Xcode 能显示 **有符号的栈**（能看到 `ViewController` 方法名，不是满屏地址）。

### 5.1 练习用崩溃（用完关掉）

页面已有红色 **Crash (W13)** 按钮，动作是抛 `NSException`（`SignDemoLab`）。用完可删按钮或注释 `crashButtonTapped:`。需要自己改时也可写成：

```objc
NSAssert(NO, @"SignDemo lab crash");
```

或：

```objc
@throw [NSException exceptionWithName:@"SignDemoLab"
                               reason:@"intentional crash for W13"
                             userInfo:nil];
```

不要 `exit()` 到后台无日志。不要留在默认流程里：做完断点实验后删按钮或注释掉。

Xcode 连着调试器时，点 Crash 会直接停在异常处。

```text
bt
```

把栈拷出来，去掉机器名、Apple ID、完整设备 UDID（可留后四位）。

### 5.2 不靠调试器的崩溃日志（可选）

若进程已经没了：Xcode → **Window → Devices and Simulators** → XR → **Open Console / View Device Logs**，找 SignDemo 最新一条。符号化后应出现你的方法名。

### 5.3 写入

```text
/Users/weideshun/Downloads/ll/reports/signdemo-crash-lldb.md
```

包含：怎么复现、脱敏后的 `bt`、为什么说已经符号化。

### 验收标准

- [x] 能保存一份脱敏崩溃记录
- [x] 栈上能认出自己的类/方法名（abort 栈仅有 main；throw 处需再抓 crashButtonTapped:）

---

## 执行 6：笔记

```text
/Users/weideshun/Downloads/ll/notes/week-13-lldb.md
```

```markdown
# W13 LLDB

## 源码断点（先停在哪）
## 符号断点
## bt 摘要
## x0 在入口 vs 返回时
## 崩溃如何复现
## 未做：越狱 debugserver
```

### 验收标准

- [x] 笔记能让一周后的自己重复操作
- [x] 没有把 debugserver 旧路径写成「一定可用」

---

## debugserver（本周只了解）

越狱后有时用 `debugserver` 让 LLDB 连已经在跑的进程。Dopamine **rootless** 下二进制位置、签名、端口和旧 jailbreak 不同。本周验收 **不依赖** 它。需要时再查当前 Dopamine 版本说明，不要抄 iOS 12 教程。

---

## 不要做的事

- 不要本周把 debugserver 当必过项。
- 不要对系统 App 下断点当作业。
- 不要把带 UDID/邮箱的原始崩溃日志提交到公开仓库。
- Crash 按钮做完就关掉，避免以后误点。

---

## 执行记录

### 执行 1：调试器连接

```text
日期：
结果：
```

### 执行 2：源码断点

```text
先停在：
Continue 后：
结果：
```

### 执行 3：符号断点

```text
符号：+[HMACSigner newNonce] → HMACSigner.m:58 resolved
loginButtonTapped: 源码断点 hit count=2
结果：完成
```

### 执行 4：x0 / bt

```text
bt：frame #0 loginButtonTapped:；下面是 UIButton/UIControl/UIApplication/main
停在 ViewController.m:360 时 register x0=0（断点在方法体内 +44，序言之后 x0 已被用掉）
self 以栈帧为准：self=0x000000010305abd0
x2 仍是 sender=0x0000000107404000
停在 +[HMACSigner newNonce] 时 x0=HMACSigner（类方法入口的接收者是类对象）
结果：完成
```

### 执行 5：崩溃

```text
报告路径：reports/signdemo-crash-lldb.md
throw 栈：-[ViewController crashButtonTapped:] at ViewController.m:441 ← sendAction ← main
abort 栈：SIGABRT，仅 SignDemo`main
结果：完成
```

### 执行 6：笔记

```text
路径：notes/week-13-lldb.md
结果：完成
```
