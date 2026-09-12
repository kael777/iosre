# W9 Mach-O 与 Ghidra：详细执行步骤

> 本文件是 [`iOS逆向_2026Q1完整实施计划.md`](../iOS逆向_2026Q1完整实施计划.md) 中“13. W9：Mach-O、代码签名和 Ghidra”的执行手册。  
> 当前环境：Mac mini 2023（Apple M2、macOS 26.6.2、Xcode 26.6）+ iPhone XR（A12、arm64e、iOS 18.5）。  
> 对象：自己编译的 **SignDemo** 主二进制。不要对商店 App 做脱壳（那是 W10）。  
> Ghidra：Homebrew formula，`ghidraRun`，依赖 JDK 21。

---

## 本周在练什么

W7/W8 是 **运行时** 看函数。W9 是 **文件上** 看同一个 App：

```text
.app Bundle
  → 主 Mach-O
  → Header / 架构 / Load Commands / cryptid
  → strings / nm / codesign
  → 导入 Ghidra
  → 搜索 HMACSigner、secret、canonical
  → 标出「伪代码可信」和「必须用 Frida 再验证」
```

SignDemo 是 **Objective-C**，方法名在符号表里是明文。这是本周的有利条件。不要指望商店 Swift App 也这么好读。

自建 Debug 包的 `cryptid` 一般是 **0**（没有 FairPlay 加密）。看到 0 不要当成「已经脱壳」，而是「自己编的本来就没加壳」。W10 再对比商店包。

---

## 当前状态

- App：`com.weideshun.SignDemo`
- 工程：`/Users/weideshun/Desktop/SignDemo/`
- 签名类：`HMACSigner`（类方法）
- 明文 secret：`local-demo-secret-v1`（第一阶段刻意硬编码）
- canonical：`user_id=&timestamp=&nonce=&action=`
- Ghidra 应已能 `ghidraRun`（环境清单 W1）
- 不要把 `.venv` 或 Ghidra 工程提交到公开仓库

---

## 本文件完成后的结果

- `artifacts/SignDemo`（从 .app 拷出的主 Mach-O，可执行文件）
- `notes/week-09-mach-o.md`
- `reports/signdemo-static-location.md`
- 本地 Ghidra Project 路径写进笔记（不要上传）

执行顺序：

```text
执行 1  从 Bundle 找到主 Mach-O 并拷贝
执行 2  file / otool 看架构和 Header
执行 3  Load Commands、cryptid、codesign
执行 4  strings / nm 初筛
执行 5  Ghidra 导入并 Auto Analyze
执行 6  定位签名相关字符串和函数
执行 7  写笔记和静态定位报告
```

---

## 执行 1：找到主 Mach-O

### 1.1 在 Xcode 产物里找

先在 Xcode 对 XR 编一次 SignDemo，然后：

```bash
find ~/Library/Developer/Xcode/DerivedData -path '*SignDemo.app/SignDemo' -type f 2>/dev/null
```

应得到类似：

```text
.../Build/Products/Debug-iphoneos/SignDemo.app/SignDemo
```

这就是主 Mach-O（没有扩展名的那个，不是 `.app` 文件夹）。

确认：

```bash
file "/path/to/SignDemo.app/SignDemo"
ls -l "/path/to/SignDemo.app"
```

`.app` 是目录。主二进制文件名通常和产品名相同：`SignDemo`。

### 1.2 拷到实验室目录

DerivedData 会被 Clean 掉。拷一份：

```bash
mkdir -p /Users/weideshun/Downloads/ll/artifacts
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*SignDemo.app/SignDemo' -type f | head -1)
echo "$APP"
cp "$APP" /Users/weideshun/Downloads/ll/artifacts/SignDemo
file /Users/weideshun/Downloads/ll/artifacts/SignDemo
```

后面命令都对这个拷贝跑。不要分析 `/Applications` 里的系统 App。

### 1.3 验收标准

- [x] 能指出 `.app` 是 Bundle 目录
- [x] 能指出其中的主 Mach-O 文件
- [x] `artifacts/SignDemo` 存在，`file` 显示 Mach-O

---

## 执行 2：架构和 Header

```bash
cd /Users/weideshun/Downloads/ll/artifacts
file SignDemo
otool -hv SignDemo
```

记下：

```text
file 输出：
cputype / subtype（应为 ARM64 / arm64）：
MH_MAGIC_64 还是 FAT（多架构）：
MH_EXECUTE / MH_PIE 等标志：
```

真机包应是 **arm64**（XR 是 A12）。若看到 `x86_64` 或 `arm64` simulator，说明拷错了 `Debug-iphonesimulator`。应选 `Debug-iphoneos`。

### 验收标准

- [x] 能说出这是 64 位 ARM Mach-O
- [x] 能区分 iphoneos 和 simulator 产物

---

## 执行 3：Load Commands、cryptid、代码签名

### 3.1 Load Commands 和加密标记

```bash
otool -l SignDemo | less
otool -l SignDemo | grep -A 6 LC_ENCRYPTION_INFO
```

64 位包实际名字可能是 `LC_ENCRYPTION_INFO_64`，grep 不到时改搜这个。

关注：

```text
LC_SEGMENT_64 / __TEXT / __DATA
LC_LOAD_DYLIB（链了哪些库）
LC_ENCRYPTION_INFO 或 LC_ENCRYPTION_INFO_64
  cryptoff
  cryptsize
  cryptid
```

自建 SignDemo 预期 **`cryptid 0`**：未用 FairPlay 加密。  
`cryptid 1` 才是商店加密段，W10 才处理。

若 grep 没有 `LC_ENCRYPTION_INFO`，也记下来：有的构建不带这一项，同样表示没有 FairPlay 壳。

### 3.2 代码签名

```bash
codesign -dvvv SignDemo
```

记下：

```text
Identifier=com.weideshun.SignDemo
TeamIdentifier=（免费账号那一串）
Format=（bundled 还是单文件；拷出来的可能是 thin Mach-O）
CodeDirectory / Hash type
Signature=adhoc 或开发者签名
```

对 **拷出来的单文件** 跑 `codesign`，有时会显示与完整 `.app` 不完全一样。需要 Bundle 级信息时：

```bash
codesign -dvvv /path/to/SignDemo.app
```

### 3.3 验收标准

- [x] 能解释 Load Commands 是「文件里的加载说明书」
- [x] 能说出本包 `cryptid` 的值以及含义（自建 = 未加壳）
- [x] 能从 `codesign` 读出 Bundle ID

### 3.4 实测记录（2026-09-11）

分析文件：`/Users/weideshun/Downloads/ll/artifacts/SignDemo`（从 `SignDemo.app` 拷出的主 Mach-O）。

**file / Header（执行 2）**

```text
file: Mach-O 64-bit executable arm64
magic: MH_MAGIC_64
cputype: ARM64 ALL
filetype: EXECUTE
ncmds: 26
flags: NOUNDEFS DYLDLINK TWOLEVEL PIE
```

**加密段（执行 3）**

```text
cmd: LC_ENCRYPTION_INFO_64
cryptoff: 16384
cryptsize: 81920
cryptid: 0
```

**代码签名（执行 3，对单文件）**

```text
Identifier=com.weideshun.SignDemo
Format=Mach-O thin (arm64)
Hash type=sha256
TeamIdentifier=3ZYFJVL464
Authority=Apple Development（免费/开发证书，不是 App Store 分发签）
Info.plist=not bound
Sealed Resources=none
```

`Info.plist=not bound` 是因为分析对象是拷出来的瘦二进制，不是完整 `.app`。Bundle ID 仍能从 Identifier 读到。

### 3.5 这些术语是什么

| 术语 | 这次看到的值 | 说明 |
|---|---|---|
| **Mach-O** | `Mach-O 64-bit executable` | macOS / iOS 可执行文件格式，类似 Windows 的 PE、Linux 的 ELF。`.app` 是文件夹（Bundle），真正被 CPU 执行的是里面这份 Mach-O。 |
| **MH_MAGIC_64** | Header magic | 文件开头的魔数：这是 **64 位、单架构** 镜像。若是 FAT/Universal，一份文件里会塞 arm64 + 别的架构，`file` 会写 `universal`。 |
| **ARM64 / arm64** | cputype | iPhone 的指令集。XR 是 A12，必须用 **iphoneos** 产物。若看到 `x86_64`，那是模拟器包，不能当真机分析对象。 |
| **EXECUTE** | filetype | 这是主程序（MH_EXECUTE），不是 `DYLIB`（动态库）或 `BUNDLE`（插件）。 |
| **ncmds = 26** | 26 条 Load Command | 后面 `otool -l` 列出的「加载说明书」条数：要映射哪些段、链哪些库、有没有加密、入口在哪。 |
| **NOUNDEFS** | flags | 没有未解析符号，链接完整。 |
| **DYLDLINK** | flags | 由动态链接器 `dyld` 加载，会再拉 Foundation 等系统库。 |
| **TWOLEVEL** | flags | 两级命名空间：符号同时记住「来自哪个 dylib」，减少撞名。 |
| **PIE** | flags | Position Independent Executable，加载地址会随机（ASLR）。正常 iOS App 都有。 |
| **Load Commands** | `otool -l` 的主体 | 加载器读的目录：段（`__TEXT` 代码、`__DATA` 数据）、依赖库（`LC_LOAD_DYLIB`）、加密信息、签名相关等。不是源码，是「怎么把文件装进内存」。 |
| **LC_ENCRYPTION_INFO_64** | cmd | 描述 FairPlay 加密段的那条命令。64 位用带 `_64` 的名字。 |
| **cryptoff** | 16384 | 加密区域相对文件开头的偏移。 |
| **cryptsize** | 81920 | 加密区域长度。有偏移和长度不等于正在加密。 |
| **cryptid** | **0** | **是否加密**：`0` = 未加密（自建 Xcode 包常见）；`1` = 商店 FairPlay 加密，W10 才处理。不要把 0 写成「已脱壳」。 |
| **codesign** | `codesign -dvvv` | 校验这份二进制是否被苹果证书签过、签的是谁、哈希是什么。 |
| **Identifier** | `com.weideshun.SignDemo` | 签名里的 Bundle ID，应和 Xcode 里一致。 |
| **thin (arm64)** | Format | 单架构切片。拷出主文件后常见；完整 `.app` 有时仍是 thin。 |
| **CodeDirectory / sha256** | Hash type | 对代码页做的哈希目录，系统用它检测文件是否被改。 |
| **TeamIdentifier** | `3ZYFJVL464` | 开发者团队 ID。 |
| **Apple Development** | Authority | 开发/免费证书链，用于 Xcode 装到自己的 XR。App Store 上的包会是 `Apple Distribution` 一类。 |
| **Info.plist=not bound** | 对单文件 | 这份拷贝没有把 Info.plist 封进密封资源。要看完整签名应对 `.app` 再跑 `codesign`。 |
| **Sealed Resources=none** | 对单文件 | 同上：`.app` 里的资源（nib、png）密封信息不在瘦 Mach-O 上。 |

---

## 执行 4：strings 和 nm 初筛

```bash
cd /Users/weideshun/Downloads/ll/artifacts

strings SignDemo | grep -i -E 'sign|hmac|nonce|local-demo|user_id='
nm -m SignDemo | grep -i HMACSigner
nm -m SignDemo | grep -i 'newNonce\|canonicalString\|signWithUserID'
```

预期能看到类似：

```text
local-demo-secret-v1
user_id=
+[HMACSigner newNonce]
+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]
+[HMACSigner signWithUserID:timestamp:nonce:action:secret:]
```

ObjC 符号是明文。Swift 会变成 `_$s...` 这种修饰名。SignDemo 主逻辑是 ObjC，所以本周应 **很容易** 对上 W7 的方法名。

把「strings 里出现、但还不知道谁引用」的条目单列，留给 Ghidra 交叉引用。

### 验收标准

- [x] strings 能找到 secret 或 canonical 片段
- [x] nm 能找到 `HMACSigner` 的类方法
- [x] 能说明 ObjC 名比 Swift 修饰名好认

### 4.1 实测记录（2026-09-11）

`strings SignDemo | grep -i -E 'sign|hmac|nonce|local-demo|user_id='` 里和签名真正相关的：

```text
local-demo-secret-v1
user_id=%@&timestamp=%lld&nonce=%@&action=%@
HMACSigner
canonicalStringWithUserID:timestamp:nonce:action:
hexHMACSHA256WithMessage:secret:
newNonce
signWithUserID:timestamp:nonce:action:secret:
signedBodyForAction:userID:
```

`grep sign` 还会误伤 `applicationWillResignActive:`、`resignFirstResponder` 等系统/UI 方法，和 HMAC 无关。

`nm -m SignDemo | grep HMACSigner`：

```text
+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]   __TEXT,__text
+[HMACSigner hexHMACSHA256WithMessage:secret:]                   __TEXT,__text
+[HMACSigner signWithUserID:timestamp:nonce:action:secret:]      __TEXT,__text
+[HMACSigner newNonce]                                           __TEXT,__text
_OBJC_CLASS_$_HMACSigner                                         __DATA,__objc_data
_OBJC_METACLASS_$_HMACSigner                                     __DATA,__objc_data
```

地址都在 `0x10000xxxx` 一带，和 PIE 的未重定位文件偏移一致。这些名字和 Xcode / W7 Frida 里用的 selector 对得上，没有 Swift 的 `_$s...` 修饰。

### 4.2 这些术语是什么

| 术语 | 说明 |
|---|---|
| **strings** | 从二进制里抽出可打印字节。能看到硬编码的 `local-demo-secret-v1` 和 format 串，但不知道谁引用，那是 Ghidra xref 的事。 |
| **nm** | 列符号表：函数名、类名、地址、所在段。ObjC 方法会写成 `+[类 方法:]` / `-[类 方法:]`。 |
| **`+[` / `-[`** | `+` 类方法（HMACSigner 全是这类），`-` 实例方法。和 Frida 里 `["+ newNonce"]` 同一套。 |
| **non-external** | 符号主要给本文件用，没有作为全局导出给别的 dylib。练习 App 里很常见。 |
| **`__TEXT,__text`** | 可执行代码段。四个 HMAC 实现就在这里。 |
| **`__DATA,__objc_data`** | ObjC 类对象 / 元类对象存放处。`_OBJC_CLASS_$_HMACSigner` 就是运行时的类。 |
| **`_objc_msgSend$...`** | 调用该方法时走的 stub，说明有别的代码在发这条消息（例如 `APIClient` 调 `newNonce`）。 |
| **Swift 修饰名** | 形如 `_$s7Module4Type...`。SignDemo 签名路径是 ObjC，所以本周看到的是可读 selector，不是修饰名。 |

留给 Ghidra 的：`local-demo-secret-v1` 和 `user_id=%@&timestamp=%lld&...` 是谁引用的（应能指到 `HMACSigner`）。

---

## 执行 5：Ghidra 导入

### 5.1 启动

```bash
ghidraRun
```

若提示没有 Java：按环境清单装 `openjdk@21` 并配置 `JAVA_HOME`。

### 5.2 操作顺序（照做）

```text
File → New Project → Non-Shared Project
项目目录建议：/Users/weideshun/ghidra_projects/SignDemo-W9
项目名：SignDemo-W9

File → Import File → artifacts/SignDemo
Language：AARCH64 / ARM:LE:64:v8A（若自动识别为 ARM64 就用自动的）
确认 Format = Mach-O

导入后双击文件 → 询问 Analyze？选 Yes
Analyzer 保持默认即可，ObjC 相关分析若列出则勾上
等 Auto Analyze 跑完
```

### 5.3 备份说明（写进笔记）

```text
Ghidra 工程在：/Users/weideshun/ghidra_projects/SignDemo-W9
不要提交到 git
DerivedData 不能当备份
artifacts/SignDemo 是二进制备份
```

### 5.4 验收标准

- [x] 工程能打开，已 Analyze
- [x] 架构是 ARM64，不是 x86

---

## 执行 6：定位签名流程

### 6.1 搜索字符串

Ghidra：`Search → For Strings`（或 Defined Strings）

搜：

```text
local-demo-secret-v1
user_id=
HMACSigner
```

双击字符串 → 右侧/下方 **XRefs**（交叉引用）→ 跳到引用函数。

### 6.2 搜索符号

`Symbol Tree` 或 `Search → For Strings` 不够时用：

```text
Window → Symbol Table
过滤 HMACSigner
```

应能看到 `+[HMACSigner newNonce]` 等。点进去看反编译窗口。

### 6.3 对照源码

打开 Xcode 里的 `HMACSigner.m`。Ghidra 伪代码里：

- **较可信**：方法名、字符串常量、调用了 `CCHmac`
- **必须动态验证**：寄存器里的参数顺序、timestamp 是 `long long` 还是对象、是否内联

W7 已经用 Frida 打印过 canonical 和 sign。本周在报告里写一句：

```text
Ghidra 看到：……
Frida 已验证：canonical = user_id=&timestamp=&nonce=&action=
因此哪一处伪代码可以信，哪一处是推断
```

至少标出 **一处需要动态验证的推断**（例如某条伪代码把 timestamp 显示成指针，而源码/Frida 证明是整数）。

### 6.4 验收标准

- [x] 在 Ghidra 里定位到至少一个与签名相关的函数或字符串
- [x] 能指出一处必须用 Frida/源码验证的反编译推断
- [x] 没有把 Ghidra 伪代码当成原始源码

### 6.5 实测结论（2026-09-11）

操作者已在 Ghidra（Language = AARCH64，已 Analyze）完成定位。

**较可信（和 strings / nm / 源码一致）**

- Defined Strings：`local-demo-secret-v1`、`user_id=%@&timestamp=%lld&nonce=%@&action=%@`
- Symbol Table：`+[HMACSigner newNonce]` 等四个类方法
- 这些名字与 W7 Frida、`HMACSigner.m` 对得上

**必须动态验证的一处推断**

格式串里是 `%lld`，源码是 `long long timestamp`，Frida 打印的也是整数 canonical。  
Ghidra 反编译常把第 3 个参数显示成 `undefined8` 或指针。那是反编译器的类型猜测，**不是**「timestamp 在运行时是对象」。W7 已经用 Frida 否定了「当对象用」这种读法。

结论：Ghidra 用来找函数和字符串；参数类型以源码 + Frida 为准。

---

## 执行 7：笔记和报告

### 7.1 文件

```text
/Users/weideshun/Downloads/ll/notes/week-09-mach-o.md
/Users/weideshun/Downloads/ll/reports/signdemo-static-location.md
```

`week-09-mach-o.md` 写命令输出摘要（架构、cryptid、codesign Identifier）。  
`signdemo-static-location.md` 写：字符串 → xref → 函数名 → 与 `HMACSigner.m` / Frida 的对照，以及「不可信的一处推断」。

### 7.2 脱敏

- 可以写 `local-demo-secret-v1`（本来就是练习明文）
- 不要写真实 Apple ID 邮箱；TeamIdentifier 可写后四位或整段（不是秘密，但不必扩散）
- 不要上传 Ghidra 工程

### 7.3 验收标准

- [x] 能从 App Bundle 找到主 Mach-O
- [x] 能解释 cryptid、Load Commands 和架构
- [x] 能在 Ghidra 中定位至少一个与签名流程相关的函数或字符串
- [x] 能指出一处需要动态验证的反编译推断

---

## 和前几周的关系

| 已完成 | W9 怎么用 |
|---|---|
| W7 Frida 打印 canonical | 验证 Ghidra 推断 |
| HMACSigner 源码 | 对照伪代码 |
| 自建包 cryptid=0 | 为 W10 对比商店包打底 |
| UnCrackable `do_it` | 可选：同一套 otool 看它的 Mach-O，本周主线仍是 SignDemo |

下一阶段进入 [`10-W10-脱壳概念-静态动态-详细执行步骤.md`](10-W10-脱壳概念-静态动态-详细执行步骤.md)。W9 **不要** 对第三方 IPA 跑 dump。

---

## 不要做的事

- 不要分析微信、银行、商店 App 的主二进制。
- 不要把 `cryptid 0` 写成「已脱壳」。
- 不要跳过 `file`/`otool` 直接只玩 Ghidra。
- 不要把 Ghidra 工程或完整 `.app` 丢进 git。
- Frida 17 本周不是主线；要用也只做「验证一处推断」。

---

## 执行记录

### 执行 1：找到 Mach-O

```text
日期：2026-09-11
主 Mach-O 拷贝：/Users/weideshun/Downloads/ll/artifacts/SignDemo
file 输出：Mach-O 64-bit executable arm64
结果：完成
```

### 执行 2：架构

```text
cputype：ARM64 ALL
magic：MH_MAGIC_64（非 FAT）
filetype：EXECUTE
flags：NOUNDEFS DYLDLINK TWOLEVEL PIE
是否 iphoneos：是（真机 arm64，不是 x86_64 simulator）
结果：完成
```

### 执行 3：cryptid / 签名

```text
cryptid：0（LC_ENCRYPTION_INFO_64，自建未加壳，不是已脱壳）
cryptoff：16384  cryptsize：81920
Identifier：com.weideshun.SignDemo
TeamIdentifier：3ZYFJVL464
Format：Mach-O thin (arm64)
Authority：Apple Development
结果：完成
```

### 执行 4：strings / nm

```text
命中的字符串：local-demo-secret-v1；user_id=%@&timestamp=%lld&nonce=%@&action=%@
HMACSigner 符号：+newNonce / +canonicalString... / +hexHMACSHA256... / +signWithUserID...（均在 __TEXT,__text）
类对象：_OBJC_CLASS_$_HMACSigner
结果：完成。ObjC 明文符号，与 W7 Frida 方法名一致
```

### 执行 5：Ghidra

```text
Language：AARCH64（不是 x86）
Analyze：已完成
结果：完成
```

### 执行 6：定位

```text
字符串：local-demo-secret-v1；user_id=%@&timestamp=%lld&nonce=%@&action=%@
函数名：+[HMACSigner canonicalString... / hexHMACSHA256... / signWithUserID... / newNonce]
需要动态验证的推断：Ghidra 可能把 timestamp 显示成 undefined8/指针；Frida+源码证明是 long long
结果：完成
```

### 执行 7：文档

```text
notes：/Users/weideshun/Downloads/ll/notes/week-09-mach-o.md
report：/Users/weideshun/Downloads/ll/reports/signdemo-static-location.md
Ghidra 工程：本地 SignDemo-W9（不入库）
结果：完成
```
