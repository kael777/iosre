# W14 Theos 与最小 Tweak：详细执行步骤

> 本文件是 [`iOS逆向_2026完整实施计划.md`](../iOS逆向_2026完整实施计划.md) 中“18. W14：Theos 和最小 Tweak”的执行手册。  
> 设备：iPhone XR / iOS 18.5 / Dopamine **rootless**。  
> 对象：**只 Hook `com.weideshun.SignDemo`**。不要改 SpringBoard、Safari、设置。

---

## 本周在练什么

Frida 是 **临时注入**；Tweak 是编译成 **deb 插件**，装进越狱设备，App 启动时由 ElleKit/Substitute 加载。

```text
Theos 工程
→ Logos（%hook）写 Hook
→ 打成 rootless .deb
→ 装到 XR
→ 打开 SignDemo 看日志
→ 卸载，行为恢复
```

两个 Tweak 都要最小：

1. 只打生命周期日志（`viewDidLoad`）
2. 再观察一个参数（`loginButtonTapped:` 或 `loginWithUserID:password:`）

不要改返回值、不要绕过 Pinning、不要 Hook 系统 App。

---

## 术语

| 术语 | 含义 |
|---|---|
| **Theos** | 越狱开发工具链：Makefile、SDK、打包 deb。 |
| **Logos** | `%hook` / `%orig` 语法，编译前展开成 ObjC runtime Hook。 |
| **%orig** | 调用原来的方法。本周必须调用，只加日志。 |
| **Filter** | 指定注入哪个 Bundle ID。写错会进别的进程。 |
| **rootless** | Dopamine：插件装在 `/var/jb/`，不是旧的 `/Library/MobileSubstrate`。 |
| **THEOS_PACKAGE_SCHEME=rootless** | 告诉 Theos 打 rootless 包。漏了可能装不上或无效。 |
| **deb** | Debian 包。越狱上用 dpkg / Sileo 安装。 |
| **respring** | 重启 SpringBoard。有的 Tweak 要；只 Hook SignDemo 时 **杀掉 SignDemo 重开** 通常就够。 |
| **INSTALL_TARGET_PROCESSES** | NIC 问 *List of applications to terminate upon installation* 时写入 Makefile 的进程名。安装 deb 后会杀这些进程以便加载新 dylib。本周填 **SignDemo**，不要用默认的 SpringBoard。 |

---

## 当前状态

- SignDemo Bundle ID：`com.weideshun.SignDemo`
- 源码类：`ViewController`、`HMACSigner`（W7/W13 已确认）
- Mac：Apple M2，Homebrew 已有
- 越狱：Dopamine 已激活；Theos 可能尚未装

Crash (W13) 按钮若还在，本周可先注释掉，以免和 Tweak 日志搅在一起。

---

## 本文件完成后的结果

- `SignDemoTweak/`（实验室仓库里）
- 能编译出 `.deb`
- 设备上能看到自己的 `NSLog` / `os_log`
- 卸载后 SignDemo 不再打这些日志
- `notes/week-14-theos.md`

执行顺序：

```text
执行 1  安装 Theos（若尚未安装）
执行 2  创建工程，Filter 只含 SignDemo
执行 3  第一个 Tweak：viewDidLoad 打日志
执行 4  编译 rootless deb
执行 5  安装、打开 App、看日志
执行 6  第二个 Tweak：观察 Login 参数
执行 7  卸载并恢复
执行 8  写笔记
```

---

## 执行 1：安装 Theos

在 Mac 上（不要在 iPhone 里装 Theos）：

```bash
echo $THEOS
ls "$THEOS/bin/nic.pl" 2>/dev/null || ls /opt/theos/bin/nic.pl 2>/dev/null
```

若没有，按 [Theos 官方 Installation](https://theos.dev/docs/installation-macos) **当前文档** 安装，不要抄 2018 年博客。常见是：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

装完后新开终端：

```bash
echo $THEOS
$THEOS/bin/nic.pl
```

能出 NIC 菜单即可。SDK / iOS 18 若不匹配，把完整报错贴出来，不要改去 Hook 系统进程。

### 验收标准

- [x] `$THEOS` 有值，`nic.pl` 能跑

---

## 执行 2：创建工程，锁死 Filter

仓库里建（不要建在 100MB 的桌面 `.venv` 旁边也行，最终要进 `ll`）：

```bash
cd /Users/weideshun/Downloads/ll
$THEOS/bin/nic.pl
```

选 **iphone/tweak**。建议填写：

```text
Project Name: SignDemoTweak
Package Name: com.weideshun.signdemotweak
Author: 你自己
Bundle filter: com.weideshun.SignDemo
```

NIC 最后常问：

```text
List of applications to terminate upon installation
(space-separated, '-' for none) [SpringBoard]:
```

**不要直接回车。** 默认 `[SpringBoard]` 会在装包后杀掉桌面、等于 respring，本周没 Hook 系统。

| 填写 | 效果 |
|---|---|
| `SignDemo` | 只杀掉自己的 App，下次打开会加载新 Tweak（推荐） |
| `-` | 不自动杀任何进程，需要自己把 SignDemo 上滑划掉再开 |
| `SpringBoard`（默认） | 重启整个 SpringBoard，没必要 |

这里填的是 **进程名 / 可执行文件名**（Xcode 产品名 `SignDemo`），不是 Bundle ID `com.weideshun.SignDemo`。

若 NIC 问 Logos 文件名，用 `Tweak.x`。

写入 Makefile 后应能看到类似：

```make
INSTALL_TARGET_PROCESSES = SignDemo
```

打开 `SignDemoTweak/SignDemoTweak.plist`（或 `*.plist` 里 Filter 那段），必须是：

```xml
<key>Filter</key>
<dict>
  <key>Bundles</key>
  <array>
    <string>com.weideshun.SignDemo</string>
  </array>
</dict>
```

**不要**写 `com.apple.springboard`。

Makefile 加上 rootless（若 NIC 没写）：

```make
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64
TARGET := iphone:clang:latest:15.0
```

`INSTALL_TARGET_PROCESSES` 可写 `SignDemo`。

### 验收标准

- [x] Filter 只有 `com.weideshun.SignDemo`
- [x] Makefile 有 `THEOS_PACKAGE_SCHEME = rootless`

---

## 执行 3：第一个 Tweak（只打日志）

`Tweak.x` 先只要：

```objc
#import <UIKit/UIKit.h>

%hook ViewController

- (void)viewDidLoad {
    NSLog(@"[SignDemoTweak] viewDidLoad self=%@", self);
    %orig;
}

%end
```

必须 `%orig`。类名与源码一致：`ViewController`。

### 验收标准

- [x] Hook 只有生命周期，没有改返回值

---

## 执行 4：编译 deb

```bash
cd /Users/weideshun/Downloads/ll/SignDemoTweak
make clean
make package
```

成功时 `packages/` 下会有 `.deb`。文件名常带 `iphoneos-arm64`（rootless）。

失败时把 **从 error 起的整段** 贴出来。常见：THEOS 未 export、缺 SDK、不是 rootless。

### 验收标准

- [x] 能编译出 deb

---

## 执行 5：安装并看日志

### 5.1 安装

XR 解锁，Dopamine 已注入。任选一种当前环境能用的方式：

- 电脑 `scp` 把 deb 拷到手机，`ssh` 后 `dpkg -i`（rootless 设备上 `dpkg` 多在 `/var/jb/usr/bin/dpkg`）
- 或用 Sileo / Zebra 的「安装本地 deb」

具体 SSH 端口、用户名以你手机上 OpenSSH 设置为准，**不要抄旧教程的 `mobile@` 万能命令**。装不上就把报错贴出来。

### 5.2 看日志

杀掉 SignDemo（上滑划掉），再打开。不要以为要 respring 才生效。

Mac 上：

```bash
# Xcode → Window → Devices → Open Console
# 或：
log stream --device --predicate 'eventMessage CONTAINS "SignDemoTweak"'
```

手机也可看：打开 SignDemo 后用 Console.app 选 XR，过滤 `SignDemoTweak`。

应出现：`[SignDemoTweak] viewDidLoad`。

### 验收标准

- [x] 能在测试设备安装
- [x] 能看到自己的日志

---

## 执行 6：第二个 Tweak（观察参数）

在同一个工程改 `Tweak.x`，不要新建乱 Filter 的工程：

```objc
#import <UIKit/UIKit.h>

%hook ViewController

- (void)viewDidLoad {
    NSLog(@"[SignDemoTweak] viewDidLoad");
    %orig;
}

- (void)loginButtonTapped:(id)sender {
    NSLog(@"[SignDemoTweak] loginButtonTapped: sender=%@", sender);
    %orig;
}

%end
```

仍 `%orig`。重新 `make package`、安装、划掉 SignDemo、打开、点 Login。日志里应有 `loginButtonTapped`。

不要 Hook `SpringBoard` 或改 `newNonce` 返回值。

### 验收标准

- [x] 点 Login 能看到第二条日志
- [x] 没有改签名结果（Login 仍 200）

---

## 执行 7：卸载并恢复

```text
Sileo 里卸载 SignDemoTweak
或 dpkg -r com.weideshun.signdemotweak
```

划掉 SignDemo 再开。Console 里 **不应再出现** `[SignDemoTweak]`。Login / Health 仍可用。

记下：安装时间、卸载时间、卸载后无插件日志。

### 验收标准

- [x] 能卸载并恢复原始 App 行为

---

## 执行 8：笔记

```text
/Users/weideshun/Downloads/ll/notes/week-14-theos.md
```

```markdown
# W14 Theos

## Theos 路径 / rootless
## Filter Bundle ID
## 第一个 Tweak 日志原文
## 第二个 Tweak 日志原文
## deb 文件名
## 如何安装 / 卸载
## 卸载后是否还有插件日志
```

`.deb` 可以留在 `SignDemoTweak/packages/`，不要把临时 `obj/` 提交 git。可在根 `.gitignore` 加：

```text
SignDemoTweak/.theos/
SignDemoTweak/packages/
SignDemoTweak/obj/
```

### 验收标准

- [x] 笔记能让别人按同样 Filter 重做
- [x] 明确写了只 Hook SignDemo

---

## 不要做的事

- 不要 Filter 写成 SpringBoard。
- 不要 `%hook` 系统类当作业（`UIApplication` 可以后再谈）。
- 不要在 Tweak 里 `return` 掉 `%orig` 去改登录结果。
- 不要本周做 ElleKit 源码级开发。
- Theos 安装以官方文档为准。

---

## 执行记录

### 执行 1：Theos

```text
日期：2026-09-11
THEOS：/Users/weideshun/theos
问题：bin/nic.pl 是断掉的 submodule 符号链接；git submodule foreach reset --hard 后可用
结果：nic.pl 能跑。不要在 $THEOS 目录里 nic.pl
```

### 执行 2：工程 / Filter

```text
Bundle：com.weideshun.SignDemo（plist Filter 已确认）
INSTALL_TARGET_PROCESSES：SignDemo
TARGET：已从 7.0 改为 15.0
rootless：已加 THEOS_PACKAGE_SCHEME = rootless；ARCHS = arm64
结果：完成
```

### 执行 3–4：编译

```text
deb：packages/com.weideshun.signdemotweak_0.0.1-1+debug_iphoneos-arm64.deb
架构：iphoneos-arm64（rootless）
结果：完成
```

### 执行 5：日志

```text
viewDidLoad 日志：[SignDemoTweak] viewDidLoad self=<ViewController: 0x101c70000>
安装：Sileo 本地 deb
结果：完成
```

### 执行 6：Login 参数

```text
日志：[SignDemoTweak] loginButtonTapped: sender=<UIButton: ...>
Login 是否仍 200：是（%orig，未改返回值）
结果：完成
```

### 执行 7：卸载

```text
卸载后还有 SignDemoTweak 日志？：无
结果：完成
```

### 执行 8：笔记

```text
路径：notes/week-14-theos.md
结果：完成
```
