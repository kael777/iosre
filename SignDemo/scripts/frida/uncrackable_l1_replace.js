// UnCrackable L1 执行 5：只改 do_it 的 char * 返回值。
// 不要和 uncrackable_l1_observe.js 一起加载。不要 ObjC.Object(retval)。
// do_it 只在启动时走一次，必须 spawn。
//
//   frida -U -f com.weideshun.uncrackable1 \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/uncrackable_l1_replace.js
//
// 输入框填：frida-replaced-secret
// 应出现 Congratulations! 退出 Frida 重开 App 后再填同一串应失败。

console.log("[*] uncrackable_l1_replace.js loaded");

const REPLACED = "frida-replaced-secret";
const retained = [];

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
    console.log("[-] 没找到 do_it，确认是源码 Debug 包且必须 spawn");
    return;
  }

  Interceptor.attach(addr, {
    onLeave: function (retval) {
      let original = "(null)";
      if (!retval.isNull()) {
        try {
          original = retval.readCString();
        } catch (error) {
          original = "(unreadable)";
        }
      }
      const buf = Memory.allocUtf8String(REPLACED);
      retained.push(buf);
      retval.replace(buf);
      console.log("[+] do_it()");
      console.log("    原返回值 = " + original);
      console.log("    改为     = " + REPLACED);
      console.log(">>> 填入输入框: " + REPLACED);
    }
  });
  console.log("[*] hooked do_it @ " + addr);
}

try {
  hookDoIt();
} catch (error) {
  console.log("[-] hookDoIt 失败: " + error);
}
