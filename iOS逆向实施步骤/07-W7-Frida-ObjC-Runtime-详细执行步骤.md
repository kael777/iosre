# W7 Frida 与 ObjC Runtime：详细执行步骤

> 本文件是 [`iOS逆向_2026Q1完整实施计划.md`](../iOS逆向_2026Q1完整实施计划.md) 中“11. W7：Frida JavaScript 基础和 ObjC Runtime”的执行手册。  
> 当前环境：Mac mini 2023（Apple M2、macOS 26.6.2、Xcode 26.6）+ iPhone XR（A12、arm64e、iOS 18.5）。  
> 当前路线：Dopamine 越狱 + Frida 17.17 + 自建 SignDemo。  
> 操作范围：只 Hook `com.weideshun.SignDemo`。不要对系统 App、商店 App 改返回值。

---

## 本周在练什么

W4–W6 已经会 **跑** Frida。W7 要练的是：每次 Hook 都能说清这四件事：

```text
Hook 的是哪个类、哪个方法？
self / 参数是什么？
返回值是什么？
这个 Hook 怎么拆掉、App 怎么恢复？
```

实验顺序固定，不要跳到最后一步：

```text
1. 列类
2. 列方法
3. Hook 无参数方法
4. Hook 一个对象参数方法
5. 打印返回值
6. 最后才改返回值
```

前五步都是 **只读观察**。改返回值只做一次最小实验，然后退出 Frida 确认 App 恢复。

---

## 当前状态

截至 2026-09-11，M1 已完成。笔记：[`notes/week-06-m1.md`](../notes/week-06-m1.md)。

- Bundle ID：`com.weideshun.SignDemo`
- 工程：`/Users/weideshun/Desktop/SignDemo/`
- 反调试开关：**保持关闭**
- Frida：17.17.0。不要用 `Module.findExportByName`
- spawn 时不要在脚本加载阶段调用 `NSBundle`、不要包装 `completionHandler`、不要 Hook BOOL 的 getter/setter（W4 已闪退过）

本周主要盯这些 **自己的** 类（以 Xcode 源码为准）：

| 类 | 类型 | 本周用途 |
|---|---|---|
| `ViewController` | 实例 | `viewDidLoad`、按钮点击 |
| `HMACSigner` | 类方法 | canonical / HMAC / nonce |
| `APIClient` | 实例 | `loginWithUserID:password:completion:` |
| `PinningURLSessionDelegate` | 实例 | 本周可列方法，但不要再改 Pinning 逻辑 |
| `AntiDebug` | 类方法 | 可列，不要打开开关 |

---

## 本文件完成后的结果

- `scripts/frida/list_runtime_methods.js`
- `scripts/frida/hook_network_request.js`
- `notes/week-07-frida-runtime.md`
- 能区分实例方法和类方法
- 能打印 `NSString` / `NSDictionary`
- 能写出 Hook 导致闪退的两个原因（用自己踩过的）

执行顺序：

```text
执行 1  环境、attach/spawn、列类
执行 2  列方法，分清实例 / 类方法
执行 3  Hook 无参数方法
执行 4  Hook 带对象参数的方法
执行 5  打印返回值
执行 6  改一次返回值并恢复
执行 7  写笔记
```

---

## 执行 1：环境、列类

### 1.1 准备

XR 解锁，SignDemo 在前台。反调试 **关**。

```bash
frida-ps -Uai | grep -i signdemo
```

应看到 `com.weideshun.SignDemo`。

优先 **attach**（App 已起来，避开 spawn 早期崩溃）：

```bash
frida -U -n SignDemo
```

名字不对就用 `frida-ps` 里的那一列。REPL 里先试：

```javascript
ObjC.available
```

应为 `true`。

### 1.2 列自己的类

在 REPL：

```javascript
Object.keys(ObjC.classes).filter(function (name) {
  return /ViewController|HMACSigner|APIClient|Pinning|AntiDebug|APIConfig|APIResponse/.test(name);
})
```

至少要看到 `ViewController`、`HMACSigner`、`APIClient`。

`ObjC.choose` 找活着的实例（App 已显示主界面之后）：

```javascript
ObjC.choose(ObjC.classes.ViewController, {
  onMatch: function (obj) {
    console.log(obj);
  },
  onComplete: function () {}
});
```

应至少命中 1 个。

### 1.3 脚本

文件：

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/list_runtime_methods.js
```

第一版只做：确认 ObjC 可用、打印上面这些类是否存在、`choose` ViewController 的个数。不要一上来 Hook 网络。

加载：

```bash
frida -U -n SignDemo \
  -l /Users/weideshun/Desktop/SignDemo/scripts/frida/list_runtime_methods.js
```

若用 spawn：脚本顶层不要发 ObjC 消息，用 `setImmediate` 再列类（W4 教训）。

### 1.4 验收标准

- [x] `ObjC.available === true`
- [x] 能列出 `ViewController`
- [x] `choose` 能找到实例
- [x] 反调试仍关闭

### 1.5 失败处理

- 进程立刻没了：反调试是否被打开；改回 attach 而不是 spawn。
- 没有 `ViewController`：确认装的是自己编的 SignDemo，不是旧包。
- `TypeError: not a function`：又用了 Frida 16 的 API。

---

## 执行 2：列方法，分清实例方法和类方法

### 2.1 规则

ObjC 在 Frida 里：

```text
实例方法：-[ViewController viewDidLoad]
类方法：  +[HMACSigner newNonce]
```

取 implementation：

```javascript
ObjC.classes.ViewController["- viewDidLoad"]
ObjC.classes.HMACSigner["+ newNonce"]
```

不要把 `+` 写成 `-`。`HMACSigner` 的签名方法全是类方法。

### 2.2 要列出的方法

在 `list_runtime_methods.js` 里对每个目标类打印 `$ownMethods`（或过滤后的方法名）。对照 Xcode：

**ViewController（实例）**

```text
- viewDidLoad
- healthButtonTapped:
- loginButtonTapped:
- profileButtonTapped:
- orderButtonTapped:
```

**HMACSigner（类方法）**

```text
+ canonicalStringWithUserID:timestamp:nonce:action:
+ hexHMACSHA256WithMessage:secret:
+ signWithUserID:timestamp:nonce:action:secret:
+ newNonce
```

**APIClient（实例）**

```text
- loginWithUserID:password:completion:
- profileWithUserID:completion:
- healthWithCompletion:
```

记下：哪个是实例方法，哪个是类方法，触发动作是什么。

### 2.3 验收标准

- [x] 能口头区分 `+` 和 `-`
- [x] 列表里能指认 `ViewController` 和 `HMACSigner` 各一个方法
- [x] 没有对系统类（如 `NSString`）做批量 Hook

---

## 执行 3：Hook 无参数方法（只打印）

### 3.1 目标

```text
-[ViewController viewDidLoad]
+[HMACSigner newNonce]
```

`viewDidLoad` 在 attach 时可能已经执行过。要看到它：用 spawn，或先 Hook 再杀进程重开。`newNonce` 在每次 Login / Order 时会进。

### 3.2 写法（观察，不改返回值）

```javascript
const VC = ObjC.classes.ViewController;
Interceptor.attach(VC["- viewDidLoad"].implementation, {
  onEnter: function (args) {
    const self = new ObjC.Object(args[0]);
    console.log("[+] -[ViewController viewDidLoad] self=" + self);
  }
});

const Signer = ObjC.classes.HMACSigner;
Interceptor.attach(Signer["+ newNonce"].implementation, {
  onEnter: function (args) {
    console.log("[+] +[HMACSigner newNonce]");
  },
  onLeave: function (retval) {
    console.log("    nonce = " + new ObjC.Object(retval).toString());
  }
});
```

点 **Login** 应看到 `newNonce`。不要 `retval.replace`。

### 3.3 记录模板

```text
目标方法：
所在类：
实例 / 类方法：
触发动作：
进入次数：
self：
返回值：
是否改行为：否
```

### 3.4 验收标准

- [x] 至少 Hook 成功一个无参数方法
- [x] 能打印 self 或返回的 NSString
- [x] App 不闪退

---

## 执行 4：Hook 带对象参数的方法

### 4.1 目标

```text
-[ViewController loginButtonTapped:]
-[APIClient loginWithUserID:password:completion:]
```

ObjC 调用约定（arm64，Frida `args`）：

```text
args[0]  self
args[1]  _cmd
args[2]  第一个参数
args[3]  第二个参数
...
```

所以 `loginWithUserID:password:completion:`：

```text
args[2]  userID   (NSString)
args[3]  password (NSString)
args[4]  completion block  ← 本周不要包装这个 block
```

### 4.2 安全打印

```javascript
function safeStr(value) {
  if (value === null || value === undefined || value.isNull()) {
    return "(nil)";
  }
  try {
    return new ObjC.Object(value).toString();
  } catch (error) {
    return "(unreadable)";
  }
}

const APIClient = ObjC.classes.APIClient;
Interceptor.attach(APIClient["- loginWithUserID:password:completion:"].implementation, {
  onEnter: function (args) {
    console.log("[+] -[APIClient loginWithUserID:password:completion:]");
    console.log("    userID = " + safeStr(args[2]));
    console.log("    password = " + safeStr(args[3]));
  }
});
```

密码是虚构 `demo-password`，可以打出来对照。不要把真实密码写进笔记。

**不要** `new ObjC.Block(args[4])` 再改 `implementation`。W4 bypass 第一版就是这样闪退的。

点 Login，终端应出现 `userID = demo-user-001`。

### 4.3 验收标准

- [x] 能打印至少一个 NSString 参数
- [x] 没有包装 completion block
- [x] 登录仍然成功

---

## 执行 5：打印返回值

### 5.1 目标

```text
+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]
+[HMACSigner signWithUserID:timestamp:nonce:action:secret:]
```

`onLeave` 里 `retval` 是 `NSString *`。

```javascript
Interceptor.attach(Signer["+ canonicalStringWithUserID:timestamp:nonce:action:"].implementation, {
  onEnter: function (args) {
    this.userID = safeStr(args[2]);
    this.action = safeStr(args[5]);
  },
  onLeave: function (retval) {
    console.log("[+] +canonicalString action=" + this.action);
    console.log("    " + new ObjC.Object(retval).toString());
  }
});
```

`timestamp` / `nonce` 是标量或对象，以源码为准：`timestamp` 是 `long long`，在 `args` 里可能是寄存器里的整数，不要强行 `ObjC.Object`。读不懂就只打印 `userID` 和返回的 NSString。

点 Login / Order。canonical 应类似：

```text
user_id=demo-user-001&timestamp=...&nonce=...&action=login
```

这就是 W6 脚本里那条字符串。把 Frida 打出来的和 `sign_login.py` 的规则对一下。

NSDictionary：可在 `APIResponse` 的 `displayText` 或 login 完成回调里看到 JSON；本周有 NSString 即可，有字典更好。

### 5.2 把观察脚本收进

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/hook_network_request.js
```

内容应包括：列到的网络/签名相关方法 + 只读 Hook。不要改 sign，不要改 Pinning。

### 5.3 验收标准

- [x] 能打印 canonical 或 sign 的 NSString
- [x] 能说明这是返回值，不是参数
- [x] 请求仍然被后端接受

---

## 执行 6：最后才改返回值（一次，然后恢复）

### 6.1 范围

只改 `+[HMACSigner newNonce]` 或 login 的 `password` 参数做一次对照，二选一即可。

推荐：把 `newNonce` 的返回值改成固定 `"frida-fixed-nonce"`，发两次 Login：

1. 第一次应成功
2. 第二次同一 nonce 应 409（和 W6 防重放一致）

```javascript
onLeave: function (retval) {
  retval.replace(ObjC.classes.NSString.stringWithString_("frida-fixed-nonce"));
}
```

改错类型（把 NSString 换成数字指针）会闪退。

### 6.2 必须恢复

```text
Frida 里 exit
或杀掉 SignDemo 不带脚本启动
再 Login 一次：应 200，nonce 不再是 frida-fixed-nonce
```

不要把 `replace` 留在 `hook_network_request.js` 的默认版本里。观察脚本保持只读；改返回值单独复制一份或用 REPL 临时做。

### 6.3 验收标准

- [x] 改返回值的效果能解释
- [x] 退出 Hook 后行为恢复
- [x] 没有改系统 API 的返回值

---

## 执行 7：笔记

### 7.1 文件

```text
/Users/weideshun/Downloads/ll/notes/week-07-frida-runtime.md
```

必须包含：

```markdown
# W7 Frida ObjC Runtime

## 环境
## 找到的类
## 实例方法 vs 类方法（各举一例）
## Hook 记录
## 打印过的 NSString / NSDictionary
## 改返回值实验与恢复
## Hook 导致闪退的两个原因
## 未验证项
## 下一步
```

闪退原因用自己做过的，不要抄网上清单。至少写：

1. spawn 阶段发 ObjC 消息 / Hook BOOL getter-setter（W4 bypass）
2. 包装 `completionHandler` 或把 JS `null` 传进 ObjC
3. （可选）对未知指针 `ObjC.Object`、错误的 `retval.replace` 类型

### 7.2 产物

```text
scripts/frida/list_runtime_methods.js
scripts/frida/hook_network_request.js
notes/week-07-frida-runtime.md
```

### 7.3 验收标准

- [x] 能找到自己的 ViewController
- [x] 能区分实例方法和类方法
- [x] 能打印一个 NSString、NSDictionary 或 NSData
- [x] 能解释 Hook 导致 App 闪退的两个原因

---

## 和前几周的关系

| 已完成 | W7 怎么用 |
|---|---|
| W4 观察/bypass 闪退 | 当本周「不要做」的反面教材 |
| HMACSigner | 类方法 + 返回值观察 |
| APIClient login | 对象参数 |
| W6 签名脚本 | 和 Frida 打出的 canonical 对照 |
| 反调试开关 | 保持关 |

下一阶段进入 [`08-W8-Native-Hook-UnCrackable-L1-详细执行步骤.md`](08-W8-Native-Hook-UnCrackable-L1-详细执行步骤.md)。W7 不要开始改 `do_it` 的返回值当主线。

---

## 不要做的事

- 不要打开 SignDemo 反调试。
- 不要包装 `NSURLSession` 的 `completionHandler`。
- 不要 `Module.findExportByName`。
- 不要批量 Hook `NSString` / `NSURLSession` 全部方法。
- 不要对第三方 App 改返回值。
- 不要把改 sign 的脚本当成默认观察脚本。

---

## 执行记录

### 执行 1：列类

```text
日期：
attach 还是 spawn：
ViewController 是否找到：
choose 个数：
结果：
```

### 执行 2：列方法

```text
实例方法例：
类方法例：
结果：
```

### 执行 3：无参数 Hook

```text
方法：
输出：
结果：
```

### 执行 4：对象参数

```text
方法：
userID：
结果：
```

### 执行 5：返回值

```text
canonical / sign：
结果：
```

### 执行 6：改返回值

```text
改了什么：
退出后是否恢复：
结果：
```

### 执行 7：笔记

```text
路径：
两个闪退原因：
结果：
```
