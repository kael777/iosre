// SignDemo W4 靶场实验：只绕过自己的证书 Pinning。
// 仅允许：com.weideshun.SignDemo
//
// spawn 阶段不要发 ObjC 消息（NSBundle / 属性赋值会把进程打掉）。
// 等脚本加载完成后再挂 Hook。
//
// frida -U -f com.weideshun.SignDemo \
//   -l /Users/weideshun/Desktop/SignDemo/scripts/frida/bypass_signdemo_pinning.js

console.log("[*] bypass script file loaded");

function safeStr(value) {
  if (value === null || value === undefined) {
    return "(nil)";
  }
  try {
    if (value.isNull && value.isNull()) {
      return "(nil)";
    }
    return new ObjC.Object(value).toString();
  } catch (error) {
    try {
      return value.toString();
    } catch (ignored) {
      return "(unreadable)";
    }
  }
}

function hookDidReceiveChallenge() {
  const Delegate = ObjC.classes.PinningURLSessionDelegate;
  const sel = "- URLSession:didReceiveChallenge:completionHandler:";
  if (Delegate === undefined || Delegate[sel] === undefined) {
    throw new Error("PinningURLSessionDelegate 或 didReceiveChallenge 还没有");
  }

  Interceptor.attach(Delegate[sel].implementation, {
    onEnter: function (args) {
      const self = new ObjC.Object(args[0]);
      const challenge = new ObjC.Object(args[3]);
      const space = challenge.protectionSpace();
      try {
        self.setPinningEnabled_(0);
      } catch (error) {
        console.log("    setPinningEnabled_ 失败: " + error);
      }
      console.log("[+] didReceiveChallenge");
      console.log("    host = " + safeStr(space.host()));
      console.log("    authenticationMethod = " + safeStr(space.authenticationMethod()));
    }
  });

  console.log("[*] hooked " + sel);
}

function tryHook(attempt) {
  if (!ObjC.available) {
    if (attempt < 20) {
      setTimeout(function () { tryHook(attempt + 1); }, 200);
    } else {
      console.log("[-] ObjC 一直不可用");
    }
    return;
  }

  try {
    hookDidReceiveChallenge();
    console.log("[*] bypass 已就绪。开着代理点 Health。");
  } catch (error) {
    console.log("[-] hook 失败: " + error);
    if (attempt < 20) {
      setTimeout(function () { tryHook(attempt + 1); }, 200);
    }
  }
}

setImmediate(function () {
  tryHook(0);
});
