# DVIA-v2 URL Scheme

## 环境

- 日期：2026-09-11
- App：`com.weideshun.dviav2`
- Scheme（Info.plist `CFBundleURLSchemes`）：`dvia`、`dviaswift`

## 攻击面

URL Scheme 让 **任意能发出该 URL 的地方**（Safari、备忘录、其它 App）打开本 App 并带上参数。若 `application:openURL:` **不看** `sourceApplication`、不校验 path，就会把外部输入当成安全决策。

## 复现

源码按 `/phone/call_number/` 切开，第二段能转成 `Int` 就弹成功：

```text
dvia://phone/call_number/10086
→ Success! Calling 10086. Ring Ring !!!
```

```text
dvia://phone/call_number/abc
→ 不弹成功（Int 解析失败）
```

没有检查来源。这里是演示弹窗，不是真的 CallKit 拨号，但决策已经在客户端根据 URL 做完了。

## 修复建议（针对此类逻辑）

- 校验 `options[.sourceApplication]` 或改用 Universal Link + 服务端确认
- 不要仅凭 URL 数字就执行敏感动作；最多预填，需用户再确认
- DVIA 作对照靶场，本周未改 DVIA 源码
