# iOS 逆向学习环境搭建 · 安装清单与 Todo（Mac mini 2023 + iPhone XR）

> 目标阶段：先【协议/签名逆向】→ 后【App 安全审计】→ 最后【越狱/漏洞研究】
> 本文档用于在**全新（运营机无开发链）**的 Mac mini 上从零搭建。所有命令在 Mac 上执行（Terminal.app）。
> 纪律：对象 = 自己设备 + 靶场练习 App，**不需要书面授权**；动他人线上资产才需要。
> **实测进度（2026-09-09）**：已选择并成功完成路线 A，在 iPhone XR 上安装/激活 Dopamine。关键经验：下载 Dopamine 时需要开启**全局 VPN**网络，普通网络无法顺利完成下载。

---

## 0. 前置确认（先做，决定两条路线走哪条）★

| # | 确认项 | 在哪看 | 记录结果 |
|---|--------|--------|---------|
| 0.1 | Mac mini macOS 版本 | 左上角  → 系统设置 → 通用 → 关于本机 | **macOS 26.6.2** ✅（已确认）|
| 0.2 | Mac 芯片（应为 M2/M2 Pro）| 同上 | **Apple M2** ✅（已确认）|
| 0.3 | **iPhone XR 的 iOS 版本（精确到小版本）** | 手机 设置 → 通用 → 关于本机 → 软件版本 | **iOS 18.5** ✅（已确认）|
| 0.4 | 磁盘剩余空间 | Mac 系统设置 → 通用 → 存储 | ≥ 30 GB 建议 |
| 0.5 | 有 Apple ID（免费开发者即可）| 手机/电脑 设置 | ______ |

> **✅ 版本决策（2026-09 核对，路线 A 已实测成功）：**
> - XR = **A12（arm64e）** + **iOS 18.5** → 已成功安装/激活 Dopamine，确定走 **路线 A：Dopamine 越狱（rootless）+ Frida**。
> - 关键网络条件：下载 Dopamine 时开启 Mac 的**全局 VPN**；这一步是本次实际遇到的主要问题。
> - 越狱前先在 Mac 上做一次 iPhone 备份（Finder 全量）；以 Dopamine 官方 GitHub Releases 最新支持表为最终准（设备×固件偶有细分例外）。
> - 路线 B（FridaGadget 免越狱重签名）暂不需要，保留为备选。

---

## 1. 安装顺序总览（Todo）

| 序 | 步骤 | 时间 | 完成 |
|----|------|------|------|
| 1 | 系统准备：更新 + 空间检查 | 10 min | ✅ |
| 2 | Command Line Tools | 5–10 min | ✅ |
| 3 | Homebrew | 5–15 min | ✅ |
| 4 | 核心逆向工具（frida / ghidra / mitmproxy / objection）| 20–40 min | ✅ |
| 5 | 抓包证书链路（mitmproxy CA → XR 信任）| 15 min | ✅ |
| 6 | 靶场 App（UnCrackable / DVIA）+ 安装到 XR | 20–30 min | ☐（源码编译路线已确定，XR 安装待验收） |
| 7 | 路线 A：Dopamine 越狱 | 40–90 min | ✅（2026-09-09；下载 Dopamine 需全局 VPN）|
| 7' | 路线 B：FridaGadget 免越狱注入 | 40–60 min | 暂不走 |
| 8 | 验收：`frida-ps -U` 能看到 App 进程 | 5 min | ✅ |

---

## 2. 详细命令

### 2.1 系统准备
```bash
# 系统更新到最新（稳定即可）
softwareupdate --all --install --restart   # 或 GUI：系统设置 → 通用 → 软件更新

# 检查空间
df -h /
```

### 2.2 Command Line Tools（基础编译链，必装）
```bash
xcode-select --install
# 弹出安装窗口 → 点安装 → 等完成
xcode-select -p    # 应输出 /Library/Developer/CommandLineTools → 装好了
```

### 2.3 Homebrew（Apple Silicon 装到 /opt/homebrew）
```bash
# 官方安装（2026 年仍适用；如网络慢可换镜像源，先试官方）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 装完按提示把 brew 加入 PATH（Apple Silicon 默认如下）
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

brew --version    # 验收
brew doctor       # 无重大告警即可
```

### 2.4 核心逆向工具
```bash
# 抓包代理
brew install mitmproxy

# Java（Ghidra 12+ 依赖 JDK 21 LTS）
brew install openjdk@21
sudo ln -sfn "$(brew --prefix openjdk@21)/libexec/openjdk.jdk" \
  /Library/Java/JavaVirtualMachines/openjdk-21.jdk
java -version    # 验收

# 静态反编译（Ghidra；2026 更正：不用 cask，使用 Homebrew formula）
brew install ghidra
ghidraRun        # 验收：能启动 GUI

# Python3（macOS 自带，确认版本；objection/frida 客户端依赖）
python3 --version   # ≥ 3.9 即可，否则 brew install python@3.12

# Frida 客户端 + objection（用 pip，比 brew 的 frida 新且稳）
pip3 install --upgrade pip
pip3 install frida frida-tools objection

# 验收
frida --version
objection version
```

> 可选补充（先不用装）：`brew install idb-companion`、`brew install --cask wireshark`。  
> Charles 不是必须项：已有 mitmproxy 就能完成主线抓包；只有想要商业 GUI 抓包工具做对比/临时替代时，再考虑 `brew install --cask charles`（也可选 Proxyman）。

### 2.5 Xcode（当前主线必需）
```bash
# 完整 Xcode 从 App Store 下载（约 12 GB+）。
# 当前主线需要它来编译 SignDemo 和源码版 UnCrackable，
# 后续还要用它做原生调试、LLDB 和 DVIA 源码安装。
# 安装后首次打开并接受协议。
xcodebuild -version
```

### 2.6 抓包证书链路（mitmproxy）
```bash
# 启动代理（终端挂着）
mitmweb --listen-port 8080
# 首次会生成 ~/.mitmproxy/mitmproxy-ca-cert.pem

# XR 与 Mac 连同一 Wi-Fi：
#   手机 设置 → Wi-Fi → 点当前网络 i → 配置代理 → 手动
#   服务器 = Mac 的局域网 IP（ifconfig en0 | grep inet），端口 8080
# 手机 Safari 打开 http://mitm.it → 下载 iOS 证书 → 安装
# 关键：设置 → 通用 → 关于本机 → 证书信任设置 → 开启 mitmproxy 证书完全信任
# 验证：手机浏览器开 https://example.com，mitmweb 界面能看到请求即成功
```

### 2.7 靶场 App（练习对象，不需要授权）
- **OWASP iOS UnCrackable L1**：
  - 官方页面：https://mas.owasp.org/crackmes/iOS/#ios-uncrackable-l1
  - 源码仓库：https://github.com/OWASP/mas-crackmes
- **DVIA-v2（Damn Vulnerable iOS App）**：GitHub `prateek147/DVIA-v2`（可自行用源码 + Xcode 编译安装，也是练习重签名的好素材）
- 说明：UnCrackable 设计目标 = 绕过 root 检测 + 提取隐藏密钥，正好覆盖协议/审计两阶段入门。当前优先使用源码工程，不再依赖旧 IPA 直链。

### 2.7' 把 UnCrackable 安装到 XR
> iOS 不能像 Android 那样直接点 IPA 安装。当前 OWASP IPA 的内置 provisioning profile 已过期，不能直接用 Xcode 安装。主线不再依赖 AppSync：使用 OWASP 源码工程，在 Xcode 中选择自己的免费 Apple Account、改 Bundle Identifier 后编译到 XR。

```bash
# 1) 获取源码
git clone https://github.com/OWASP/mas-crackmes.git
cd "mas-crackmes/iOS/Level1"
open "UnCrackable Level 1.xcodeproj"

# 2) 手机准备
# 数据线连接 Mac → iPhone 点“信任此电脑”
# iOS 16+：设置 → 隐私与安全性 → 开发者模式 → 开启并按提示重启

# 3) Xcode 中选择 XR，配置 Team、Bundle Identifier 和自动签名后点击 Run（⌘R）
```

> 如果提示 `Unable to Install`、`Untrusted Developer` 或 `profile invalid`：先检查免费账号、Bundle Identifier、开发者模式和设备信任状态。`This provisioning profile has expired` 针对的是旧 IPA，当前源码编译流程不会复用它。

### 2.8 路线 A：越狱（rootless）—— XR iOS 版本在支持区间时
```bash
# 官方入口（2026-09-09）：
#   网站/下载/安装指南：https://ellekit.space/dopamine/
#   官方源码与 Releases：https://github.com/opa334/Dopamine/releases
# XR 是 A12 设备；是否支持以官网 Compatibility 和当前 release 说明为准
# 1) Mac 侧先装好依赖工具
brew install libimobiledevice
# 2) 按官网 Installation Guide 把 Dopamine 安装到 XR，再在设备上打开 Dopamine
#    点击 Jailbreak；重启后需要重新打开 Dopamine 并再次点击 Jailbreak
# 3) 越狱后：Sileo（包管理器）添加 Frida 官方源 https://build.frida.re → 安装 Frida
# 4) 验收
frida-ps -U        # 列出 XR 上进程 → 环境通
```
> **实测记录（2026-09-09）**：Dopamine 已在本机 XR 上成功安装/激活。下载 Dopamine 时必须开启 Mac 的**全局 VPN**；遇到下载失败或卡住时先检查这一点。`frida-ps -U` 已能看到 XR 进程；`frida-ps -Uai` 和目标 App attach 仍需单独验收。
> ⚠️ 越狱属于"自己设备上的操作"，无授权问题，但注意：会触发 App 完整性/支付风控、Apple 政策风险；练习 App 不受影响。**越狱前先备份**。

#### 2.8.1 越狱路线安装 UnCrackable IPA（当前不走 AppSync）
> **2026-09-10 实测/核对**：`https://cydia.akemi.ai/` 当前在本环境也会超时；它仍是 AppSync Unified 作者 README 标注的官方源，但不能当成稳定可访问入口。更关键的是，官方最新 AppSync Unified 116.0 的包元数据写着 `firmware (<= 18.2)`，而本机 XR 是 **iOS 18.5**。所以当前不要继续卡 AppSync，主线改为用 Xcode + 免费 Apple Account 安装源码版 UnCrackable。

```bash
# 推荐路线：源码编译安装，不需要付费 Apple Developer
# 1) Mac 开全局 VPN 后下载源码
git clone https://github.com/OWASP/mas-crackmes.git

# 2) 用 Xcode 打开官方 iOS UnCrackable L1 工程
cd "mas-crackmes/iOS/Level1"
open "UnCrackable Level 1.xcodeproj"
#    工程实际位于 iOS/Level1/UnCrackable Level 1.xcodeproj，
#    App 源码位于 iOS/Level1/UnDebuggable/
#    打开工程后：
#      Signing & Capabilities → Team 选择你的免费 Apple Account
#      Bundle Identifier 改成一个属于自己的唯一值，例如：
#        com.weideshun.uncrackable1
#      Automatically manage signing 勾选
#      运行目标选择 XR，不选 Simulator
#      点击 Run（⌘R）安装到 XR

# 如果编译报：
#   SDK does not contain 'libarclite' ...
# 这是旧工程的最低 iOS 部署版本太低（原工程仍是 iOS 8/10）。
# 修复：
#   1) 左侧蓝色工程图标 → PROJECT 和 TARGETS 都分别点开
#   2) Build Settings 搜索 “iOS Deployment Target”
#   3) 把工程和 App Target 的 Debug/Release 值都改为 iOS 18.0
#      （XR 是 iOS 18.5；也可使用不低于当前 SDK 要求的其他版本）
#   4) 不要手动填写旧的 ARCHS/VALID_ARCHS；保持 Xcode 默认的 Standard Architectures
#   5) Product → Clean Build Folder（按住 Option 后打开 Product 菜单）
#   6) 再选择 XR，点击 Run（⌘R）

# 3) 验收
frida-ps -Uai | grep -i uncrackable
```

> 这里的“免费 Apple Account”不是付费 Apple Developer Program。免费账号也能用 Xcode 把自己编译的 App 安装到自己的设备，只是签名有效期通常较短。越狱已解决 Frida attach/hook 能力，但并不自动解决任意过期 IPA 的安装签名问题；这仍需要 AppSync 这类 installd 绕过，而 AppSync 当前不适合本机 iOS 18.5。

> **本次错误的具体原因**：官方工程的 `IPHONEOS_DEPLOYMENT_TARGET` 仍包含 Target `8.0`、项目配置 `10.2`，而当前 Xcode SDK 不再提供这些旧部署目标需要的 `libarclite_iphoneos.a`。针对本机 XR（iOS 18.5），将工程和 Target 的 Debug/Release 统一改到 iOS 18.0，再清理构建目录即可。

> **若下一步安装时报“不兼容设备”**：打开 `UnDebuggable/Info.plist`，找到 `UIRequiredDeviceCapabilities`，旧工程里的 `armv7` 面向老设备；可删除这一项，或改为 `arm64`，然后重新 Build。iPhone XR 是 arm64e，运行 arm64 App。

> **AppSync 仅作为后续备选**：如果 AppSync 官方源恢复且官方 Release 明确支持 iOS 18.5，再考虑安装。官方源是 `https://cydia.akemi.ai/`，官方 Releases 是 https://github.com/akemin-dayo/AppSync/releases/latest。不要安装第三方改包源；作者 README 明确警告第三方修改版可能破坏系统稳定性。Dopamine/rootless 设备应选择 `iphoneos-arm64` 包，不要选 `iphoneos-arm`。

### 2.8' 路线 B：免越狱（FridaGadget 重签名）—— XR 版本不支持越狱时
```bash
# 下面这一步不是为了开发临时 App，而是让 Xcode 生成一个：
#   1) 用你的 Apple Development 证书签名
#   2) 包含 XR UDID
#   3) Bundle ID 为 sg.vp.UnCrackable1
#   4) 尚未过期
# 的开发 provisioning profile，供 objection 重签 UnCrackable IPA 使用。
#
# A. 在 Xcode 登录 Apple 账号
#    Xcode → Settings → Apple Accounts → “+” → 登录 Apple Account
#
# B. 新建临时 iOS App
#    File → New → Project → iOS → App → Next
#    Product Name：UnCrackableProfileSeed
#    Team：选择刚登录的账号
#    Organization Identifier：sg.vp
#    Bundle Identifier：确认最终显示为 sg.vp.UnCrackable1
#      若 Product Name 自动带来别的后缀，稍后在 Signing & Capabilities 中手动改掉
#    Interface：SwiftUI
#    Language：Swift
#    其余选项保持默认，保存到任意临时目录
#
# C. 为临时 App 开启自动签名
#    左侧点蓝色工程图标 → TARGETS 下选择临时 App
#    Signing & Capabilities → 勾选 Automatically manage signing
#    Team：选择你的 Apple 账号
#    Bundle Identifier：sg.vp.UnCrackable1
#    不要添加 iCloud、Push、App Groups 等额外 Capability
#
# D. 连接 XR 并让 Xcode 成功运行一次
#    数据线连接 XR；手机点“信任此电脑”，输入锁屏密码
#    iOS 16+：设置 → 隐私与安全性 → 开发者模式 → 开启并重启
#    Xcode 顶部运行目标选择 XR（不是 iPhone Simulator）
#    点击 Run（⌘R）
#    若出现 Register Device / Set Up Signing，点击 Register / Set Up
#    如果手机弹出“信任开发者”，到：
#      设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任
#    临时 App 能在 XR 上启动一次后，这一步就完成了

# E. 在终端找到 Xcode 刚生成的有效 profile
find ~/Library/Developer/Xcode/DerivedData \
  -path '*/Build/Products/Debug-iphoneos/*/embedded.mobileprovision' \
  -print

# 选择刚才临时 App 对应的 embedded.mobileprovision，检查它的关键信息
security cms -D -i "/上一步找到的/embedded.mobileprovision" \
  -o /tmp/uncrackable-profile.plist
plutil -p /tmp/uncrackable-profile.plist | \
  grep -E 'application-identifier|com.apple.developer.team-identifier|ExpirationDate|ProvisionedDevices'

# 检查可用签名身份；复制 Apple Development 那一行前面的长串 SHA-1
security find-identity -v -p codesigning

# 找到刚由 Xcode 生成的有效 profile；优先选刚才空白 App 对应的那个
find ~/Library/Developer/Xcode/DerivedData -name embedded.mobileprovision -print

# 1) objection 注入 FridaGadget，同时替换过期 profile 并重签名
objection patchipa --source UnCrackable-Level1.ipa \
  --codesign-signature 0123456789ABCDEF0123456789ABCDEF01234567 \
  --provision-file "/上一步找到的/embedded.mobileprovision"
# 输出通常为：UnCrackable-Level1-frida-codesigned.ipa

# 2) 装到 XR（Xcode Devices and Simulators → Installed Apps → +）
# 或：解压后用 ios-deploy 安装
unzip -q UnCrackable-Level1-frida-codesigned.ipa -d patched
npm install -g ios-deploy
ios-deploy --bundle patched/Payload/UnCrackable1.app

# 3) 用 frida 连接 Gadget
frida-ps -U        # 或 frida -U -f com.xxx --no-pause -l hook.js
```
> `objection patchipa` 需要有效的 `embedded.mobileprovision`；若自动找不到，先用 Xcode 成功运行一次空白 App，再重新执行。免费 Apple ID 签名通常约 7 天后失效，需要重新生成/安装；付费 Apple Developer 账号的有效期更长。`objection` 官方文档也要求 macOS/Xcode、开发证书和有效 provisioning profile。

---

## 3. 验收标准（全绿 = 环境就绪）

```bash
brew --version          # ✔
xcode-select -p         # ✔
frida --version         # ✔
frida-ps -U             # ✔ 能看到 XR 进程（含 SpringBoard 等）
objection version       # ✔
mitmproxy --version     # ✔ + 手机经代理能访问 https
```

---

## 4. 合规备忘（练习阶段）

- ✅ 可做：自己设备越狱；逆向练习靶场 App；Frida 观察自己登录 App 的请求（不绕过支付、不外传数据）。
- ❌ 不做：对任何第三方生产后端/服务器探测或打请求；分发抓到的数据；用公开 exploit 打真实目标。
- 后面做真实项目的安全审计时，先落 scope + 书面授权（届时走我的授权流程）。

---

## 5. 下一步建议（装到哪一步告诉我，我继续带你）

1. 0.1–0.3 三个版本号先发我 → 我帮你定【越狱 A】还是【免越狱 B】，以及核对 Dopamine 3 支持表
2. 装到 2.4 后跑一遍"验收"命令，把输出贴回来
3. 环境通后，我出 **UnCrackable L1 动手脚本包**（Frida hook + mitmproxy + 判据）
