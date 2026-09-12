# W19 反调试与越狱检测

## 环境

- 日期：2026-09-12
- XR + Dopamine rootless + SignDemo
- 报告：[`reports/anti-analysis-lab.md`](../reports/anti-analysis-lab.md)
- 脚本：`scripts/frida/observe_jailbreak_checks.js`

## 三句话

1. **三层**：签名（谁签的包）≠ 反调试（`P_TRACED`）≠ 越狱检测（路径 / scheme / dylib）。
2. **漏报**：这台 Dopamine 上 Cydia 路径、`sshd`、镜像名含 `frida` 都是 NO；命中的是 `/var/jb`、Sileo、Filza、ellekit、TweakInject。
3. **XOR** 让 `strings` 看不到 `/var/jb`，Frida 仍能看到还原后的 path。客户端检测替代不了 W17/W18 服务端校验。

## 下一步

Q1 复盘：[`Q1-review.md`](Q1-review.md)。Q2 计划：[`iOS逆向_2026Q2完整实施计划.md`](../iOS逆向_2026Q2完整实施计划.md)。反调试开关保持关闭。
