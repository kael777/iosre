# W13 LLDB

## 环境

- 日期：2026-09-11
- Xcode 连 XR Debug 运行 SignDemo（不是越狱 debugserver）

## 源码断点

- `-[ViewController loginButtonTapped:]` at ViewController.m:360，hit count ≥ 2
- Continue 后能进 `+[HMACSigner newNonce]`（HMACSigner.m:58）

## 符号断点

```text
(lldb) breakpoint set -n "+[HMACSigner newNonce]"
```

解析到 `HMACSigner.m:58`。`+` 是类方法，不能写成 `-`。命令在 Xcode 底部 `(lldb)` 控制台执行，不是系统终端。

## bt 摘要

Login：`loginButtonTapped:` ← `UIButton sendAction` ← `UIApplication` ← `main`。

Crash：`crashButtonTapped:` ← 同样的 UIKit 点击链 ← `main`。

## x0 在入口 vs 返回时

| 停在哪 | `x0` |
|---|---|
| `loginButtonTapped:` 方法体内 +44 | 寄存器已是 0；`self` 看栈帧 `self=0x...` |
| `+[HMACSigner newNonce]` 入口附近 | 类对象 `HMACSigner`（类方法的接收者） |

函数中间不要盲信 `register read x0`。入口才是 self/类；返回时才是返回值。

## 崩溃如何复现

按钮 **Crash (W13)** 抛 `NSException SignDemoLab`。  
在 `crashButtonTapped:` 下断点再点，`bt` 能看到该方法。`continue` 后变成 SIGABRT，栈上只剩 `main`。  
记录：`reports/signdemo-crash-lldb.md`。

## 未做

越狱 debugserver（Dopamine rootless 路径不固定，本周不依赖）。

## 下一步

进入 [`iOS逆向实施步骤/14-W14-Theos-最小Tweak-详细执行步骤.md`](../iOS逆向实施步骤/14-W14-Theos-最小Tweak-详细执行步骤.md)。Crash 按钮实验完应删掉或注释。
