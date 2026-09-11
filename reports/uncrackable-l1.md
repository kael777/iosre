# UnCrackable L1（源码版）

## 环境与 Bundle ID

- 日期：2026-09-11
- 设备：iPhone XR / iOS 18.5 / arm64e / Dopamine
- 工程：`/Users/weideshun/Documents/mas-crackmes/iOS/Level1/`（`UnDebuggable/`）
- Bundle Identifier：`com.weideshun.uncrackable1`
- Frida：17.17.0
- 安装路线：Xcode + 免费 Apple Account 编译到 XR，不用过期 IPA，不用 `sg.vp.UnCrackable1`

密钥来自 `do_it()` 的返回值，是靶场字符串，不是真实密码。报告里不重复粘贴该串；以观察脚本的 `>>> 填入输入框` 为准。

## 安装失败 vs 逻辑失败

| 种类 | 表现 | 处理 |
|---|---|---|
| 安装失败 | Xcode 签不了、libarclite、未信任开发者、免费账号过期、`frida-ps` 看不到包 | 改 Bundle ID / Deployment Target、Clean、再 Run |
| 靶场逻辑失败 | 主界面已出来，Verify 后弹 `Verification Failed.` | 输入不等于隐藏 label，属于校验分支 |

主界面能停留、有 Verify，就说明安装已经成功。不要把错误口令当成「没装上」。

## 静态结论（有无越狱检测）

阅读 `ViewController.m`、`maxpower.h`、`AppDelegate.m`：

- **没有**独立越狱/root 弹窗，没有 `isJailbroken` 一类逻辑。网上 IPA 教程不能直接套到这份源码。
- **没有**在 ObjC 层看到 `ptrace` / 反调试退出。
- 密钥不在 `buttonClick:` 里计算，而在 `viewDidLoad` 调用 C 函数 `do_it()`。
- `theLabel.hidden = YES`，比较用 `isEqualToString:`。

`maxpower.c` 是混淆生成代码，本周把它当成「`do_it` 返回一串 ASCII」，不要求读懂。

## 调用链草图

```text
UIApplication
  → ViewController viewDidLoad
      → do_it()                         [C / Native，char *]
      → theLabel.text = hiddenText
      → theLabel.hidden = YES
  → 用户点 Verify
      → buttonClick:
          → theTextField.text isEqualToString: theLabel.text
              → YES：Congratulations! / You found the secret!!
              → NO ：Verification Failed. / This is not the string you are looking for. Try again.
```

检测点就是这条比较，不是越狱检测。

## Frida 观察（do_it / label / buttonClick）

脚本（只读）：

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_observe.js
```

`do_it` 只在启动时走一次，必须 spawn：

```bash
frida -U -f com.weideshun.uncrackable1 \
  -l /Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_observe.js
```

- Native：`Interceptor.attach(do_it)`，`retval.readCString()`，不用 `ObjC.Object`
- 找符号：Frida 17 的 `findGlobalExportByName` / `getGlobalExportByName` / `enumerateSymbols`，不用 `findExportByName`
- `viewDidLoad` 结束后 `theLabel.text` 与 `do_it` 返回值相同，`hidden = true`
- 输入 `wrong` 点 Verify：`isEqualToString = false`，走失败弹窗

动态确认：`do_it` 确实执行，隐藏 label 就是那次返回值。

## 成功与失败 UI

| 输入 | 标题 | 正文 |
|---|---|---|
| `wrong` | Verification Failed. | This is not the string you are looking for. Try again. |
| 观察得到的 `do_it` / `theLabel.text` | Congratulations! | You found the secret!! |

点 OK 后 App 仍在前台，源码里没有失败即 `exit`。

## Native Hook 与 ObjC Hook 的差别

| | ObjC（W7 SignDemo） | Native（W8 `do_it`） |
|---|---|---|
| 目标 | `HMACSigner` / `APIClient` 的方法 | C 函数地址 |
| 取地址 | `ObjC.classes.X["+ method"]` | 导出/符号表 |
| 返回值 | `NSString *` → `ObjC.Object` | `char *` → `readCString()` |
| 改返回值 | `alloc/init` + `retain` + `.handle` | `Memory.allocUtf8String` + 数组留住指针 |
| 时机 | attach 后点按钮即可 | 必须 spawn，否则错过 `viewDidLoad` |

把 `char *` 当成 `NSString` 去 `ObjC.Object` 会读错或崩。

## 改返回值与恢复

单独脚本（不要写进观察脚本）：

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_replace.js
```

spawn 加载后把 `do_it` 的返回值改成 `frida-replaced-secret`（堆上 C 字符串并 retain）。输入该串，Verify 应走成功分支。退出 Frida、划掉 App 重开，再输入同一串应回到失败分支。没有改 `isEqualToString:` 让任意输入成功。

## 产物

```text
/Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_observe.js
/Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_replace.js
/Users/weideshun/Downloads/ll/reports/uncrackable-l1.md
```

## 未验证项

- 未分析 UnCrackable L2/L3。
- 未对商店 App 做 Native Hook。
- 未把 `maxpower.c` 反混淆读成算法。
- 未进入 W9 的 Ghidra / Mach-O 主线（见 [`iOS逆向实施步骤/09-W9-Mach-O-Ghidra-详细执行步骤.md`](../iOS逆向实施步骤/09-W9-Mach-O-Ghidra-详细执行步骤.md)）。
