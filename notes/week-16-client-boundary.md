# W16 客户端入口边界

## 环境

- 日期：2026-09-11
- DVIA：`com.weideshun.dviav2` scheme `dvia` / `dviaswift`
- InsecureApp：`insecureapp://`
- 免费账号 3 App：DVIA 与 InsecureApp 轮流安装

## 三句话

1. **URL Scheme**：谁都能发 `dvia://...`；不校验来源就把参数当拨号/登录，就是攻击面。
2. **WebView Bridge**：`postMessage` 进原生等于把网页当成可信代码。
3. **本地认证**：Face ID 失败后用 `skipBiometrics` 放行，等于没认证。

## 修复

InsecureApp：Scheme 忽略登录、去掉 `nativeLogin`、生物识别不再读 skip 键。回归：Safari / 网页 / 改 plist 都不能自动登录。

## 下一步

进入 [`iOS逆向实施步骤/17-W17-API重放-详细执行步骤.md`](../iOS逆向实施步骤/17-W17-API重放-详细执行步骤.md)。只打本机 SignDemo 后端。
