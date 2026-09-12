// SignDemo W19：只观察越狱/反调试检测点，不改返回值、不 exit。
// Bundle ID：com.weideshun.SignDemo
// Frida 17 不要用 Module.findExportByName。不要 replace。不要包装 block。
//
// 优先 App 已在前台再 attach（点 Jailbreak Check 即可）：
//   frida -U -n SignDemo \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/observe_jailbreak_checks.js
//
// spawn：
//   frida -U -f com.weideshun.SignDemo \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/observe_jailbreak_checks.js

console.log("[*] observe_jailbreak_checks.js loaded");

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

function interestingPath(path) {
  const lower = String(path).toLowerCase();
  return (
    lower.indexOf("cydia") !== -1 ||
    lower.indexOf("/var/jb") !== -1 ||
    lower.indexOf("sileo") !== -1 ||
    lower.indexOf("filza") !== -1 ||
    lower.indexOf("substrate") !== -1 ||
    lower.indexOf("sshd") !== -1 ||
    lower.indexOf("ellekit") !== -1 ||
    lower.indexOf("frida") !== -1 ||
    lower.indexOf("tweakinject") !== -1
  );
}

function hookClassMethod(className, selector, onEnter, onLeave) {
  const cls = ObjC.classes[className];
  if (cls === undefined || cls[selector] === undefined) {
    console.log("[-] 没有 " + className + " " + selector);
    return;
  }
  Interceptor.attach(cls[selector].implementation, {
    onEnter: onEnter || function () {},
    onLeave: onLeave || function () {}
  });
  console.log("[*] hooked " + className + " " + selector);
}

function hookJailbreakCheck() {
  hookClassMethod("JailbreakCheck", "+ statusSummary", function () {
    console.log("[+] +[JailbreakCheck statusSummary]");
  }, function (retval) {
    console.log("    summary =\n" + safeStr(retval));
  });

  hookClassMethod("JailbreakCheck", "+ fileExists:", function (args) {
    console.log("[+] +[JailbreakCheck fileExists:] " + safeStr(args[2]));
  }, function (retval) {
    console.log("    -> " + (retval.toInt32() ? "YES" : "NO"));
  });

  hookClassMethod("JailbreakCheck", "+ canOpenScheme:", function (args) {
    console.log("[+] +[JailbreakCheck canOpenScheme:] " + safeStr(args[2]));
  }, function (retval) {
    console.log("    -> " + (retval.toInt32() ? "YES" : "NO"));
  });
}

function hookAntiDebug() {
  hookClassMethod("AntiDebug", "+ isBeingTraced", function () {
    console.log("[+] +[AntiDebug isBeingTraced]");
  }, function (retval) {
    console.log("    -> " + (retval.toInt32() ? "YES" : "NO"));
  });

  hookClassMethod("AntiDebug", "+ statusSummary", function () {
    console.log("[+] +[AntiDebug statusSummary]");
  }, function (retval) {
    console.log("    " + safeStr(retval));
  });
}

function hookFileExists() {
  const NSFileManager = ObjC.classes.NSFileManager;
  const sel = "- fileExistsAtPath:";
  if (NSFileManager === undefined || NSFileManager[sel] === undefined) {
    console.log("[-] 没有 -[NSFileManager fileExistsAtPath:]");
    return;
  }
  Interceptor.attach(NSFileManager[sel].implementation, {
    onEnter: function (args) {
      this.path = safeStr(args[2]);
      this.watch = interestingPath(this.path);
    },
    onLeave: function (retval) {
      if (!this.watch) {
        return;
      }
      console.log("[+] -[NSFileManager fileExistsAtPath:] " + this.path);
      console.log("    -> " + (retval.toInt32() ? "YES" : "NO"));
    }
  });
  console.log("[*] hooked -[NSFileManager fileExistsAtPath:] (filtered)");
}

function hookCanOpenURL() {
  const UIApplication = ObjC.classes.UIApplication;
  const sel = "- canOpenURL:";
  if (UIApplication === undefined || UIApplication[sel] === undefined) {
    console.log("[-] 没有 -[UIApplication canOpenURL:]");
    return;
  }
  Interceptor.attach(UIApplication[sel].implementation, {
    onEnter: function (args) {
      this.url = safeStr(args[2]);
      this.watch = interestingPath(this.url);
    },
    onLeave: function (retval) {
      if (!this.watch) {
        return;
      }
      console.log("[+] -[UIApplication canOpenURL:] " + this.url);
      console.log("    -> " + (retval.toInt32() ? "YES" : "NO"));
    }
  });
  console.log("[*] hooked -[UIApplication canOpenURL:] (filtered)");
}

function install() {
  if (!ObjC.available) {
    console.log("[-] ObjC.available = false");
    return;
  }
  console.log("[*] ObjC.available = true");
  hookJailbreakCheck();
  hookAntiDebug();
  hookFileExists();
  hookCanOpenURL();
  console.log("[*] 点 Jailbreak Check (W19)。不要关反调试以外的业务按钮。");
}

if (ObjC.available) {
  install();
} else {
  const timer = setInterval(function () {
    if (ObjC.available) {
      clearInterval(timer);
      install();
    }
  }, 50);
}
