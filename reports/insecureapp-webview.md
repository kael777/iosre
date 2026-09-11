# InsecureApp WebView、Scheme 与本地认证

## 环境

- Bundle ID：`com.weideshun.InsecureApp`
- Scheme：`insecureapp`
- 测试：虚构 `demo` / `pass`

## 修复前（执行 4）

| 入口 | 坏的行为 | 影响 |
|---|---|---|
| `insecureapp://login?user=demo` | 不看来源、不校验密码，直接 `sessionAuthenticated` | 外部 URL 即可登录 |
| WKWebView `nativeLogin` | 网页 `postMessage` 当登录成功 | 信任任意页面 JS |
| `skipBiometrics==YES` | 不调 `LAContext` 也放行 | 改 plist 绕过 Face ID |

信任边界：网页和自定义 URL **不是**已认证用户。

## 修复（执行 5）

| 入口 | 修复 | 回归 |
|---|---|---|
| Scheme | `handleInboundURL` 只打日志，不 `loginWithSource` | Safari 打开后仍未登录 |
| WebView | 去掉 `addScriptMessageHandler:nativeLogin` | 无网页登录按钮，不能设登录 |
| 生物识别 | 删除 `skipBiometrics` 短路；失败就是失败 | 改 plist 不能绕过 |

密码 Login 仍可用。操作者确认三项回归都对。

## 修复建议

- Scheme 参数最多预填，不能当已认证
- 不要把登录交给 JS Bridge；若必须有 Bridge，只加载自己的 `file://` 且权限最小化
- 本地认证失败不得用 UserDefaults 布尔放行
