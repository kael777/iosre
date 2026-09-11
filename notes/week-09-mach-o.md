# W9 Mach-O 与 Ghidra

## 环境

- 日期：2026-09-11
- 对象：自己编译的 SignDemo 主 Mach-O（iphoneos / 真机）
- 拷贝：`/Users/weideshun/Downloads/ll/artifacts/SignDemo`
- Ghidra Language：AARCH64（不是 x86）
- Ghidra 工程：本地 Non-Shared Project `SignDemo-W9`（不提交 git）

## 从 Bundle 到文件

`.app` 是目录。真正执行的是里面的 `SignDemo`（无扩展名）。DerivedData 会消失，所以拷到 `artifacts/`。

## Header 与架构

```text
file: Mach-O 64-bit executable arm64
magic: MH_MAGIC_64          64 位单架构，不是 FAT
cputype: ARM64 ALL          真机；x86_64 才是模拟器
filetype: EXECUTE           主程序
flags: NOUNDEFS DYLDLINK TWOLEVEL PIE
```

**Mach-O**：iOS 可执行格式。**Load Commands**：给 dyld 的加载说明书（映射哪些段、链哪些库、有没有加密）。**PIE**：加载地址随机。

## cryptid 与签名

```text
LC_ENCRYPTION_INFO_64
cryptoff  16384
cryptsize 81920
cryptid   0
```

**cryptid 0**：FairPlay 未加密。这是 Xcode 自建包的正常状态，不是「已脱壳」。`cryptid 1` 才是商店加密，W10 再对比。

```text
Identifier=com.weideshun.SignDemo
Format=Mach-O thin (arm64)
TeamIdentifier=3ZYFJVL464
Authority=Apple Development
Hash type=sha256
Info.plist=not bound   （因为分析的是从 .app 拷出的单文件）
```

## strings / nm

明文：`local-demo-secret-v1`，`user_id=%@&timestamp=%lld&nonce=%@&action=%@`。

符号（均在 `__TEXT,__text`，类方法 `+`）：

```text
+[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]
+[HMACSigner hexHMACSHA256WithMessage:secret:]
+[HMACSigner signWithUserID:timestamp:nonce:action:secret:]
+[HMACSigner newNonce]
```

ObjC 名字可读，没有 Swift `_$s...` 修饰。与 W7 Frida 的 selector 一致。

## Ghidra 定位

Search Strings → `local-demo-secret-v1` / `user_id=` → XRefs。  
Symbol Table 过滤 `HMACSigner` → 四个类方法 → Decompile。

**可信**：方法名、字符串常量、能对上 `HMACSigner.m`。  
**不可全信**：伪代码里 timestamp 的类型（常见 `undefined8`）。源码是 `long long`，格式串是 `%lld`，Frida 打出的 canonical 也是整数。

## 下一步

进入 [`iOS逆向实施步骤/10-W10-脱壳概念-静态动态-详细执行步骤.md`](../iOS逆向实施步骤/10-W10-脱壳概念-静态动态-详细执行步骤.md)。不要对第三方商店包 dump。本周 `cryptid 0` 只作为对照基线。
