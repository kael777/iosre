# W8 Native Hook 与 UnCrackable L1：详细执行步骤

> 本文件是 [`iOS逆向_2026完整实施计划.md`](../iOS逆向_2026完整实施计划.md) 中“12. W8：Native Hook 和 UnCrackable L1”的执行手册。  
> 当前环境：Mac mini 2023（Apple M2、macOS 26.6.2、Xcode 26.6）+ iPhone XR（A12、arm64e、iOS 18.5）。  
> 靶场：OWASP mas-crackmes 源码版 UnCrackable iOS Level 1。  
> Bundle Identifier：`com.weideshun.uncrackable1`（以 Xcode 为准）。  
> 操作范围：只分析这一份自己编译安装的练习 App。

---

## Native Hook 是什么

W7 Hook 的是 **ObjC 方法**（`ViewController`、`HMACSigner`）。W8 要加一层：**C 函数**。

这份源码里密钥不是写在 `buttonClick:` 里算出来的，而是：

```text
viewDidLoad
  → C 函数 do_it()          ← Native，返回 char *
  → NSString 放进隐藏 theLabel
buttonClick:
  → 比较 theTextField.text 和 theLabel.text
  → 成功 Congratulations! / 失败 Verification Failed.
```

`do_it` 在 `maxpower.c` 里，头文件是 `char *do_it(void);`。Frida 要用 `Interceptor.attach` 打到这个地址，用 `retval.readCString()` 读返回值，**不要** `new ObjC.Object(retval)`。

本周顺序仍是：先观察，最后才改返回值。改返回值用单独脚本，沿用 W7 的 retain / 不要 autorelease。

---

## 当前状态

截至 2026-09-11：

- 源码工程：`/Users/weideshun/Documents/mas-crackmes/iOS/Level1/`
- 已能在 XR 启动（00.2 执行 4）
- 静态阅读已做过：`ViewController.m`、`maxpower.h`（00.2 执行 5）
- 观察脚本已有：`/Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_observe.js`
- 这份 **源码版没有独立越狱弹窗**，不要按网上 IPA 教程去找 `isJailbroken`
- Frida 17：找导出用 `Module.findGlobalExportByName` / `getGlobalExportByName` / `enumerateSymbols`，不要 `findExportByName`
- spawn 加载阶段不要调 `NSBundle`

因此 W8 不是重装 App，而是把静态、观察、Native Hook、成功/失败分支收成一份报告。

---

## 本文件完成后的结果

- `reports/uncrackable-l1.md`
- `scripts/frida/uncrackable_l1_observe.js`（只读）
- `scripts/frida/uncrackable_l1_replace.js`（可选，改 `do_it` 返回值）
- 一张调用链草图
- 能区分「安装失败」和「靶场逻辑失败」

执行顺序：

```text
执行 1  确认 XR 上源码版仍能启动
执行 2  静态结论写成调用链（含「没有越狱检测」）
执行 3  只读观察 do_it / viewDidLoad / buttonClick:
执行 4  错误输入和正确输入的 UI
执行 5  （可选）改 do_it 返回值并恢复
执行 6  写报告和草图
```

---

## 执行 1：确认 App 能启动

### 1.1 核对身份

```bash
frida-ps -Uai | grep -i uncrack
```

必须是 `com.weideshun.uncrackable1`。不要打开过期 IPA 或 `sg.vp.UnCrackable1`。

XR 解锁，点开 App：应进入带输入框和 **Verify** 的主界面，不要一上来就退出。

### 1.2 装不上时才重编

只有启动失败才走安装排查。不要把签名问题当成密钥没找到。

```text
安装失败：Xcode 签名、Bundle ID、Deployment Target / libarclite、设备未信任开发者
靶场逻辑失败：主界面已出来，Verify 后弹 Verification Failed 或 Congratulations
```

免费账号过期时：Xcode 选 XR 再 Run 一次即可。

### 1.3 验收标准

- [x] `frida-ps` 能看到 `com.weideshun.uncrackable1`
- [x] 主界面能停留，有 Verify
- [x] 能用一句话区分安装失败和逻辑失败

---

## 执行 2：静态调用链

### 2.1 要读的文件

```text
UnDebuggable/ViewController.m
UnDebuggable/ViewController.h
UnDebuggable/maxpower.h
UnDebuggable/AppDelegate.m
```

`maxpower.c` 是混淆生成代码，本周 **不必读懂**。把它当成「`do_it()` 会返回一串 ASCII」。

### 2.2 记录（按源码，不要抄 IPA 博客）

```text
越狱/root 检测：有 / 无（本源码版应是无）
调试检测：有 / 无
密钥从哪来：do_it()
藏在哪：theLabel（hidden = YES）
谁比较：buttonClick: 里 isEqualToString:
成功 UI：
失败 UI：
```

调用链草图（周末产物，先在笔记里用纯文本）：

```text
main / UIApplication
  → ViewController viewDidLoad
      → do_it()                    [C / Native]
      → theLabel.text = hiddenText
      → theLabel.hidden = YES
  → 用户点 Verify
      → buttonClick:
          → theTextField.text isEqualToString: theLabel.text
              → YES：Congratulations! / You found the secret!!
              → NO ：Verification Failed. / This is not the string you are looking for. Try again.
```

### 2.3 验收标准

- [x] 能指出密钥来自 `do_it`，不是写死在 `buttonClick:`
- [x] 能说明本源码版没有独立越狱弹窗
- [x] 草图里有成功和失败两条分支

---

## 执行 3：只读 Native + ObjC 观察

### 3.1 脚本

已有：

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_observe.js
```

必须观察：

- `do_it`：onEnter / onLeave，`retval.readCString()`（不是 ObjC.Object）
- `-[ViewController viewDidLoad]`：之后读 `theLabel.text`、`theLabel.hidden`
- `-[ViewController buttonClick:]`：`theTextField.text`、`theLabel.text`、是否相等

不要 `replace`。不要包装 block。

找 `do_it` 用 Frida 17：

```javascript
Module.findGlobalExportByName("do_it")
// 或 Module.getGlobalExportByName("do_it")
// 或主模块 enumerateSymbols 过滤 do_it / _do_it
```

### 3.2 运行

`do_it` 在 `viewDidLoad` 里调用，**必须 spawn** 才能看到第一次：

```bash
frida -U -f com.weideshun.uncrackable1 \
  -l /Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_observe.js
```

停住就 `%resume`。预期先出现：

```text
[+] do_it()
    返回字符串: ...
[+] -[ViewController viewDidLoad]
    theLabel.hidden = true
    theLabel.text   = ...   （应与 do_it 返回值相同）
```

再输入 `wrong`，点 Verify：

```text
[+] -[ViewController buttonClick:]
    theTextField.text = wrong
    theLabel.text     = ...
    isEqualToString   = false
```

### 3.3 记录模板

```text
目标：do_it / viewDidLoad / buttonClick:
触发：spawn 启动 / 点 Verify
do_it 返回：
theLabel.text：
错误输入 UI：
是否改行为：否
```

### 3.4 验收标准

- [x] 动态确认 `do_it` 确实执行
- [x] `do_it` 返回值等于隐藏 label
- [x] 错误输入走失败分支
- [x] 观察阶段没有改返回值

### 3.5 失败处理

- 找不到 `do_it`：确认是 Debug 源码包；打印主模块 `enumerateSymbols` 里含 `do_it` 的名字。
- attach 看不到 `do_it`：已经执行过，改 spawn。
- `TypeError: not a function`：又用了 `Module.findExportByName`。
- spawn 秒退：脚本顶层不要 `NSBundle`。

---

## 执行 4：成功和失败 UI

### 4.1 失败（必做）

输入 `wrong`，Verify。记录弹窗标题和正文。点 OK 后 App 应还在。

### 4.2 成功

把观察脚本打出的 `theLabel.text` / `do_it()` 字符串输入再 Verify。记录 `Congratulations!`。

本周 **不要** 把密钥写进公开仓库以外的聊天记录也可以；写进 `reports/uncrackable-l1.md` 时标明这是靶场字符串。不要把它当成真实密码。

### 4.3 验收标准

- [x] 失败分支文案与源码一致
- [x] 成功分支至少验证过一次（Frida 观察得到密钥即可，不必猜）

---

## 执行 5：改 do_it 返回值（可选，单独脚本）

### 5.1 目的

证明 Native 返回值也能改，和 W7 改 `newNonce` 是同一类实验。默认观察脚本保持只读。

新文件：

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_replace.js
```

只改 `do_it` 的 `char *`。不要改系统函数。

`char *` 要用堆上的 C 字符串并自己留住指针，不能用会消失的局部缓冲：

```javascript
const retained = [];
Interceptor.attach(addr, {
  onLeave: function (retval) {
    const original = retval.readCString();
    const buf = Memory.allocUtf8String("frida-replaced-secret");
    retained.push(buf);
    retval.replace(buf);
    console.log("do_it 原值 = " + original);
    console.log("do_it 改为 = frida-replaced-secret");
  }
});
```

必须 **spawn**（`do_it` 只在启动时走一次）。

输入 `frida-replaced-secret` 再 Verify，应走成功分支。退出 Frida、重开 App，再输入同一串应失败（除非它碰巧真是密钥）。

### 5.2 不要做

- 不要 `retval.replace` 一个 JS 字符串。
- 不要把 `char *` 当成 `NSString` 去 `ObjC.Object`。
- 不要改 `isEqualToString:` 让任意输入都成功当本周主线（那是改校验，不是 Native 返回值）。

### 5.3 验收标准

- [x] 改返回值后，输入替换串能成功
- [x] 退出 Hook 重开后行为恢复
- [x] 观察脚本仍是只读

---

## 执行 6：报告

### 6.1 文件

```text
/Users/weideshun/Downloads/ll/reports/uncrackable-l1.md
```

必须包含：

```markdown
# UnCrackable L1（源码版）

## 环境与 Bundle ID
## 安装失败 vs 逻辑失败
## 静态结论（有无越狱检测）
## 调用链草图
## Frida 观察（do_it / label / buttonClick）
## 成功与失败 UI
## Native Hook 与 ObjC Hook 的差别
## 改返回值（若做了）与恢复
## 未验证项
```

脱敏：不要写第三方 App；靶场密钥可以写，标明来自 `do_it`。

### 6.2 验收标准

- [x] 源码版 App 能在 XR 启动
- [x] 能找到并解释至少一个检测点（本源码版：密钥校验；并写明无越狱检测）
- [x] 能通过动态观察确认检测点确实执行
- [x] 能解释「安装失败」和「靶场逻辑失败」的区别

---

## 和前几周的关系

| 已完成 | W8 怎么用 |
|---|---|
| 00.2 安装 + 静态 | 本周验收，不重做除非装不上 |
| W7 ObjC Hook | 继续 Hook `buttonClick:` |
| W7 `retval.replace` 闪退 | Native 用 `allocUtf8String` 并 retain 缓冲 |
| SignDemo HMAC | 对照：那是 ObjC 类方法；`do_it` 是 C |

下一阶段进入 [`09-W9-Mach-O-Ghidra-详细执行步骤.md`](09-W9-Mach-O-Ghidra-详细执行步骤.md)。W8 不要开始系统级反调试对抗。

---

## 不要做的事

- 不要用过期 IPA 当主线。
- 不要假设有越狱弹窗。
- 不要对 `do_it` 用 `ObjC.Object`。
- 不要把改返回值写进观察脚本。
- 不要分析商店 App。

---

## 执行记录

### 执行 1：启动

```text
日期：
Bundle ID：
主界面是否停留：
结果：
```

### 执行 2：静态

```text
越狱检测：
密钥来源：
比较方法：
结果：
```

### 执行 3：观察

```text
do_it 是否进入：
label 是否一致：
错误输入：
结果：
```

### 执行 4：UI

```text
失败文案：
成功文案：
结果：
```

### 执行 5：replace（可选）

```text
替换串：
退出后是否恢复：
结果：
```

### 执行 6：报告

```text
路径：
结果：
```
