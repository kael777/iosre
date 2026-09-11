// UnCrackable L1：只观察，不改返回值。
// Native：do_it() 返回 char *，用 readCString，不要 ObjC.Object。
// ObjC：viewDidLoad / buttonClick:
// Bundle ID：com.weideshun.uncrackable1
//
// do_it 只在启动时走一次，必须 spawn：
//   frida -U -f com.weideshun.uncrackable1 \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_observe.js
//
// Frida 17 不要用 Module.findExportByName。不要包装 block。不要 replace。

function safeNsString(value) {
  if (value === null || value === undefined || value.isNull()) {
    return "(nil)";
  }
  try {
    return new ObjC.Object(value).toString();
  } catch (error) {
    return "(unreadable: " + error + ")";
  }
}

function findDoIt() {
  const names = ["do_it", "_do_it"];

  if (typeof Module.findGlobalExportByName === "function") {
    for (let i = 0; i < names.length; i++) {
      const addr = Module.findGlobalExportByName(names[i]);
      if (addr) {
        return addr;
      }
    }
  }

  if (typeof Module.getGlobalExportByName === "function") {
    for (let i = 0; i < names.length; i++) {
      try {
        return Module.getGlobalExportByName(names[i]);
      } catch (error) {
      }
    }
  }

  const main = Process.enumerateModules()[0];
  if (main && typeof main.enumerateSymbols === "function") {
    const hits = main.enumerateSymbols().filter(function (symbol) {
      return symbol.name === "do_it" || symbol.name === "_do_it";
    });
    if (hits.length > 0) {
      return hits[0].address;
    }
  }

  try {
    const symbol = DebugSymbol.fromName("do_it");
    if (symbol && symbol.address && !symbol.address.isNull()) {
      return symbol.address;
    }
  } catch (error) {
    console.log("[-] DebugSymbol.fromName(do_it) failed: " + error);
  }

  return null;
}

function hookDoIt() {
  const addr = findDoIt();
  if (addr === null) {
    console.log("[-] 没找到 do_it，先确认这是源码编译的 Debug 包");
    return;
  }

  Interceptor.attach(addr, {
    onEnter: function () {
      console.log("[+] do_it()");
    },
    onLeave: function (retval) {
      console.log("    返回指针: " + retval);
      if (!retval.isNull()) {
        const secret = retval.readCString();
        console.log("    返回字符串: " + secret);
        console.log(">>> 填入输入框: " + secret);
      }
    }
  });
  console.log("[*] hooked do_it @ " + addr);
}

function hookViewController() {
  const ViewController = ObjC.classes.ViewController;
  if (ViewController === undefined) {
    console.log("[-] 没有 ObjC 类 ViewController");
    return;
  }

  Interceptor.attach(ViewController["- viewDidLoad"].implementation, {
    onEnter: function (args) {
      this.self = new ObjC.Object(args[0]);
      console.log("[+] -[ViewController viewDidLoad]");
    },
    onLeave: function () {
      try {
        const label = this.self.theLabel();
        console.log("    theLabel.hidden = " + label.isHidden());
        console.log("    theLabel.text   = " + safeNsString(label.text()));
        console.log(">>> 填入输入框: " + safeNsString(label.text()));
      } catch (error) {
        console.log("    读取 theLabel 失败: " + error);
      }
    }
  });

  Interceptor.attach(ViewController["- buttonClick:"].implementation, {
    onEnter: function (args) {
      const self = new ObjC.Object(args[0]);
      const input = self.theTextField().text();
      const secret = self.theLabel().text();
      const matched = input && secret
        ? input.isEqualToString_(secret)
        : false;

      console.log("[+] -[ViewController buttonClick:]");
      console.log("    theTextField.text = " + safeNsString(input));
      console.log("    theLabel.text     = " + safeNsString(secret));
      console.log("    isEqualToString   = " + matched);
    }
  });

  console.log("[*] hooked -[ViewController viewDidLoad]");
  console.log("[*] hooked -[ViewController buttonClick:]");
}

console.log("[*] uncrackable_l1_observe.js loaded");

try {
  hookDoIt();
} catch (error) {
  console.log("[-] hookDoIt 失败: " + error);
}

function hookObjCWhenReady(attempt) {
  if (!ObjC.available || ObjC.classes.ViewController === undefined) {
    if (attempt < 40) {
      setTimeout(function () { hookObjCWhenReady(attempt + 1); }, 50);
    } else {
      console.log("[-] ObjC ViewController 一直不可用");
    }
    return;
  }
  try {
    hookViewController();
    console.log("[*] 观察脚本已就绪。先看 do_it 输出，再输入 wrong 点 Verify");
  } catch (error) {
    console.log("[-] hookViewController 失败: " + error);
  }
}

hookObjCWhenReady(0);
