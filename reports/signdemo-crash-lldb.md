# SignDemo W13 崩溃记录（脱敏）

## 复现

1. Xcode Debug 运行 SignDemo 到 XR。
2. `(lldb) breakpoint set -n "-[ViewController crashButtonTapped:]"`
3. 点红色 **Crash (W13)**。
4. 停在方法里立刻 `bt`，不要 `continue`。

按钮里是：

```objc
@throw [NSException exceptionWithName:@"SignDemoLab"
                               reason:@"intentional crash for W13"
                             userInfo:nil];
```

## 符号化栈（throw 处，要交的这份）

`stop reason = breakpoint`，停在自己的方法里。

```text
frame #0  SignDemo  -[ViewController crashButtonTapped:]
          at ViewController.m:441
          self=ViewController  _cmd=crashButtonTapped:  sender=UIButton
frame #1  UIKitCore -[UIApplication sendAction:to:from:forEvent:]
frame #2  UIKitCore -[UIControl sendAction:to:forEvent:]
frame #3  UIKitCore -[UIControl _sendActionsForEvents:withEvent:]
frame #4  UIKitCore -[UIButton _sendActionsForEvents:withEvent:]
frame #5  UIKitCore -[UIControl touchesEnded:withEvent:]
... 触摸/手势/RunLoop ...
frame #25 UIKitCore UIApplicationMain
frame #26 SignDemo  main  at main.m:17
frame #27 dyld      start
```

能认出自己的类和方法：`crashButtonTapped:`、`main`。有源文件和行号，即已符号化。PIE 下地址每次运行会变。已去掉 UDID / Apple ID。

和 Login 的 `bt` 对照：都是按钮 → `sendAction` → 自己的 IBAction；只是这次动作是抛异常而不是发网络请求。

## 对照：停在 abort 时（continue 之后）

若在 throw 之后 `continue`，未捕获异常会变成 SIGABRT，栈变成：

```text
__pthread_kill → abort → _objc_terminate → objc_exception_rethrow
→ CFRunLoopRunSpecific → UIApplicationMain → SignDemo main
```

`crashButtonTapped:` 已经不在栈上。那是终止路径，不是抛出点。

## 结论

- 崩溃可复现。
- 要看自己的方法名：在 `crashButtonTapped:` 下断点，停住就 `bt`。
- 实验结束后删除或注释 Crash 按钮。
