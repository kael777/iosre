// SignDemo W7：只列类和方法，不 Hook、不改返回值。
// Bundle ID：com.weideshun.SignDemo
// 反调试开关保持关闭。
//
// 优先 attach（App 已在前台）：
//   frida -U -n SignDemo \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/list_runtime_methods.js
//
// spawn 时顶层不发 ObjC 消息。Frida 17 不要用 Module.findExportByName。

console.log("[*] list_runtime_methods.js loaded");

const TARGET_CLASSES = [
  "ViewController",
  "HMACSigner",
  "APIClient",
  "APIResponse",
  "PinningURLSessionDelegate",
  "AntiDebug",
  "APIConfig"
];

function listOwnMethods(className) {
  const cls = ObjC.classes[className];
  if (cls === undefined) {
    console.log("[-] 没有类 " + className);
    return;
  }

  const own = cls.$ownMethods || [];
  const instanceMethods = [];
  const classMethods = [];
  for (let i = 0; i < own.length; i++) {
    const name = own[i];
    if (name.charAt(0) === "+") {
      classMethods.push(name);
    } else {
      instanceMethods.push(name);
    }
  }

  console.log("[+] " + className);
  console.log("    实例方法 (" + instanceMethods.length + ")");
  instanceMethods.forEach(function (name) {
    console.log("      " + name);
  });
  console.log("    类方法 (" + classMethods.length + ")");
  classMethods.forEach(function (name) {
    console.log("      " + name);
  });
}

function chooseViewController() {
  const ViewController = ObjC.classes.ViewController;
  if (ViewController === undefined) {
    console.log("[-] 无法 choose：没有 ViewController");
    return;
  }

  let count = 0;
  ObjC.choose(ViewController, {
    onMatch: function (obj) {
      count += 1;
      console.log("[+] ViewController instance #" + count + " " + obj);
    },
    onComplete: function () {
      console.log("[*] ObjC.choose(ViewController) 个数 = " + count);
    }
  });
}

function run() {
  if (!ObjC.available) {
    console.log("[-] ObjC.available = false");
    return;
  }
  console.log("[*] ObjC.available = true");

  console.log("[*] 目标类是否存在：");
  TARGET_CLASSES.forEach(function (name) {
    console.log("    " + name + " = " + (ObjC.classes[name] !== undefined));
  });

  TARGET_CLASSES.forEach(listOwnMethods);
  chooseViewController();
  console.log("[*] 只读列类/列方法结束，没有 Hook");
}

setImmediate(run);
