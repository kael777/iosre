// SignDemo W7 执行 3–5：只读 Hook，不改返回值、不包装 completion block。
// -[ViewController viewDidLoad]
// +[HMACSigner newNonce]
// -[ViewController loginButtonTapped:]
// -[APIClient loginWithUserID:password:completion:]
// +[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]
// +[HMACSigner signWithUserID:timestamp:nonce:action:secret:]
//   timestamp 是 long long，不要 ObjC.Object。
//
// attach 时 viewDidLoad 可能已经跑过。要看到它请 spawn，或 Hook 后再杀进程重开。
// newNonce：attach 后点 Login / Create Test Order 即可。
//
//   frida -U -n SignDemo \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/hook_network_request.js
//
//   frida -U -f com.weideshun.SignDemo \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/hook_network_request.js
//
// 反调试保持关闭。不要包装 completionHandler。不要 Module.findExportByName。

console.log("[*] hook_network_request.js loaded");

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
    return "(unreadable)";
  }
}

function hookViewDidLoad() {
  const ViewController = ObjC.classes.ViewController;
  if (ViewController === undefined || ViewController["- viewDidLoad"] === undefined) {
    console.log("[-] 没有 -[ViewController viewDidLoad]");
    return;
  }

  Interceptor.attach(ViewController["- viewDidLoad"].implementation, {
    onEnter: function (args) {
      const self = new ObjC.Object(args[0]);
      console.log("[+] -[ViewController viewDidLoad]");
      console.log("    实例/类方法：实例方法");
      console.log("    self = " + self);
      console.log("    触发：界面加载（spawn 可见；attach 时可能已执行过）");
    }
  });
  console.log("[*] hooked -[ViewController viewDidLoad]");
}

function hookLoginButton() {
  const ViewController = ObjC.classes.ViewController;
  const sel = "- loginButtonTapped:";
  if (ViewController === undefined || ViewController[sel] === undefined) {
    console.log("[-] 没有 -[ViewController loginButtonTapped:]");
    return;
  }

  Interceptor.attach(ViewController[sel].implementation, {
    onEnter: function (args) {
      const self = new ObjC.Object(args[0]);
      console.log("[+] -[ViewController loginButtonTapped:]");
      console.log("    实例/类方法：实例方法");
      console.log("    self = " + self);
      console.log("    sender = " + safeStr(args[2]));
      console.log("    触发：点 Login");
    }
  });
  console.log("[*] hooked -[ViewController loginButtonTapped:]");
}

function hookLoginWithUserID() {
  const APIClient = ObjC.classes.APIClient;
  const sel = "- loginWithUserID:password:completion:";
  if (APIClient === undefined || APIClient[sel] === undefined) {
    console.log("[-] 没有 -[APIClient loginWithUserID:password:completion:]");
    return;
  }

  Interceptor.attach(APIClient[sel].implementation, {
    onEnter: function (args) {
      const self = new ObjC.Object(args[0]);
      console.log("[+] -[APIClient loginWithUserID:password:completion:]");
      console.log("    实例/类方法：实例方法");
      console.log("    self = " + self);
      console.log("    userID   = " + safeStr(args[2]));
      console.log("    password = " + safeStr(args[3]));
      console.log("    completion block 未包装（args[4]）");
    }
  });
  console.log("[*] hooked -[APIClient loginWithUserID:password:completion:]");
}

function readI64(value) {
  try {
    return value.toInt64().toString();
  } catch (error) {
    return String(value);
  }
}

function hookCanonical() {
  const Signer = ObjC.classes.HMACSigner;
  const sel = "+ canonicalStringWithUserID:timestamp:nonce:action:";
  if (Signer === undefined || Signer[sel] === undefined) {
    console.log("[-] 没有 " + sel);
    return;
  }

  Interceptor.attach(Signer[sel].implementation, {
    onEnter: function (args) {
      this.userID = safeStr(args[2]);
      this.timestamp = readI64(args[3]);
      this.nonce = safeStr(args[4]);
      this.action = safeStr(args[5]);
    },
    onLeave: function (retval) {
      console.log("[+] +[HMACSigner canonicalStringWithUserID:timestamp:nonce:action:]");
      console.log("    实例/类方法：类方法");
      console.log("    userID=" + this.userID + " timestamp=" + this.timestamp);
      console.log("    nonce=" + this.nonce + " action=" + this.action);
      console.log("    返回值 canonical = " + safeStr(retval));
    }
  });
  console.log("[*] hooked " + sel);
}

function hookSign() {
  const Signer = ObjC.classes.HMACSigner;
  const sel = "+ signWithUserID:timestamp:nonce:action:secret:";
  if (Signer === undefined || Signer[sel] === undefined) {
    console.log("[-] 没有 " + sel);
    return;
  }

  Interceptor.attach(Signer[sel].implementation, {
    onEnter: function (args) {
      this.userID = safeStr(args[2]);
      this.action = safeStr(args[5]);
    },
    onLeave: function (retval) {
      console.log("[+] +[HMACSigner signWithUserID:timestamp:nonce:action:secret:]");
      console.log("    实例/类方法：类方法");
      console.log("    userID=" + this.userID + " action=" + this.action);
      console.log("    返回值 sign = " + safeStr(retval));
    }
  });
  console.log("[*] hooked " + sel);
}

function hookNewNonce() {
  const Signer = ObjC.classes.HMACSigner;
  if (Signer === undefined || Signer["+ newNonce"] === undefined) {
    console.log("[-] 没有 +[HMACSigner newNonce]");
    return;
  }

  Interceptor.attach(Signer["+ newNonce"].implementation, {
    onEnter: function () {
      console.log("[+] +[HMACSigner newNonce]");
      console.log("    实例/类方法：类方法");
      console.log("    触发：Login / Create Test Order 生成 nonce");
    },
    onLeave: function (retval) {
      console.log("    返回值 nonce = " + safeStr(retval));
    }
  });
  console.log("[*] hooked +[HMACSigner newNonce]");
}

function run() {
  if (!ObjC.available) {
    console.log("[-] ObjC.available = false");
    return;
  }
  try {
    hookViewDidLoad();
    hookNewNonce();
    hookLoginButton();
    hookLoginWithUserID();
    hookCanonical();
    hookSign();
    console.log("[*] 观察已就绪。点 Login / Order 应看到 canonical 和 sign。未改返回值。");
  } catch (error) {
    console.log("[-] hook 失败: " + error);
  }
}

setImmediate(run);
