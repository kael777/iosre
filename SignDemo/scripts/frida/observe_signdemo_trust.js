// SignDemo W4：只观察 TLS Pinning 校验点，不改返回值、不绕过。
// 目标来自当前源码：PinningURLSessionDelegate.m、APIConfig.m
// Bundle ID：com.weideshun.SignDemo
//
// frida -U -f com.weideshun.SignDemo \
//   -l /Users/weideshun/Desktop/SignDemo/scripts/frida/observe_signdemo_trust.js

const DISPOSITION = {
  0: "UseCredential",
  1: "PerformDefaultHandling",
  2: "CancelAuthenticationChallenge",
  3: "RejectProtectionSpace"
};

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
      return "(unreadable: " + error + ")";
    }
  }
}

function findExport(name) {
  if (typeof Module.findGlobalExportByName === "function") {
    const addr = Module.findGlobalExportByName(name);
    if (addr) {
      return addr;
    }
  }
  if (typeof Module.getGlobalExportByName === "function") {
    try {
      return Module.getGlobalExportByName(name);
    } catch (error) {
    }
  }
  const main = Process.enumerateModules()[0];
  if (main && typeof main.enumerateSymbols === "function") {
    const hits = main.enumerateSymbols().filter(function (symbol) {
      return symbol.name === name || symbol.name === "_" + name;
    });
    if (hits.length > 0) {
      return hits[0].address;
    }
  }
  return null;
}

function readNSStringGlobal(name) {
  const addr = findExport(name);
  if (addr === null) {
    return null;
  }
  try {
    const pointer = addr.readPointer();
    if (pointer.isNull()) {
      return null;
    }
    return new ObjC.Object(pointer).toString();
  } catch (error) {
    return null;
  }
}

function wrapCompletionHandler(blockPtr, context) {
  try {
    const block = new ObjC.Block(blockPtr);
    const original = block.implementation;
    block.implementation = function (disposition, credential) {
      const name = DISPOSITION[disposition] || String(disposition);
      console.log("    completionHandler = " + name);
      if (context.expected && context.actual) {
        console.log("    fingerprint match = " + (context.actual === context.expected));
      }
      return original(disposition, credential);
    };
    return true;
  } catch (error) {
    console.log("    未能包装 completionHandler: " + error);
    return false;
  }
}

function hookPinningDelegate() {
  const Delegate = ObjC.classes.PinningURLSessionDelegate;
  if (Delegate === undefined) {
    console.log("[-] 没有类 PinningURLSessionDelegate");
    return;
  }

  const challengeSel = "- URLSession:didReceiveChallenge:completionHandler:";
  const hashSel = "- leafCertificateSHA256:";
  const expectedPin = readNSStringGlobal("SignDemoPinnedCertSHA256");

  if (expectedPin) {
    console.log("[*] SignDemoPinnedCertSHA256 = " + expectedPin);
  }

  Interceptor.attach(Delegate[hashSel].implementation, {
    onLeave: function (retval) {
      const actual = safeStr(retval);
      console.log("[+] -[PinningURLSessionDelegate leafCertificateSHA256:]");
      console.log("    actual SHA-256 = " + actual);
      if (expectedPin) {
        console.log("    expected       = " + expectedPin.toLowerCase());
        console.log("    match          = " + (actual === expectedPin.toLowerCase()));
      }
    }
  });

  Interceptor.attach(Delegate[challengeSel].implementation, {
    onEnter: function (args) {
      this.self = new ObjC.Object(args[0]);
      const challenge = new ObjC.Object(args[3]);
      const space = challenge.protectionSpace();
      const pinningEnabled = !!this.self.pinningEnabled();

      console.log("[+] -[PinningURLSessionDelegate URLSession:didReceiveChallenge:completionHandler:]");
      console.log("    host = " + safeStr(space.host()));
      console.log("    authenticationMethod = " + safeStr(space.authenticationMethod()));
      console.log("    pinningEnabled = " + pinningEnabled);

      wrapCompletionHandler(args[4], {
        expected: expectedPin ? expectedPin.toLowerCase() : null
      });
    },
    onLeave: function () {
      const reason = this.self.lastFailureReason();
      if (reason && !reason.isNull()) {
        console.log("    lastFailureReason = " + reason.toString());
      }
    }
  });

  console.log("[*] hooked -[PinningURLSessionDelegate URLSession:didReceiveChallenge:completionHandler:]");
  console.log("[*] hooked -[PinningURLSessionDelegate leafCertificateSHA256:]");
}

function hookSecTrustEvaluateWithError() {
  const addr = findExport("SecTrustEvaluateWithError");
  if (addr === null) {
    console.log("[-] 未找到 SecTrustEvaluateWithError，跳过可选观察");
    return;
  }
  Interceptor.attach(addr, {
    onEnter: function () {
      console.log("[+] SecTrustEvaluateWithError");
    },
    onLeave: function (retval) {
      console.log("    result = " + retval);
    }
  });
  console.log("[*] hooked SecTrustEvaluateWithError @ " + addr);
}

if (!ObjC.available) {
  console.log("[-] ObjC runtime 不可用");
} else {
  try {
    hookPinningDelegate();
  } catch (error) {
    console.log("[-] hookPinningDelegate 失败: " + error);
  }
  try {
    hookSecTrustEvaluateWithError();
  } catch (error) {
    console.log("[-] hookSecTrustEvaluateWithError 失败: " + error);
  }
  console.log("[*] 观察脚本已就绪。Pinning ON，先无代理点 Health，再开代理点一次。");
}
