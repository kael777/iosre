// SignDemo W7 执行 6：改一次返回值。不要当默认观察脚本。
// 只改 +[HMACSigner newNonce] → "frida-fixed-nonce"
//
// 上一版用 stringWithString_ + retval.replace(ObjC.Object) 会在 Login 时闪退：
// 便利构造的 NSString 是 autorelease，replace 又需要 NativePointer。
// 现在用 alloc/init（+1）并 retain，replace 传入 .handle。
//
//   frida -U -n SignDemo \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/replace_newNonce.js
//
// 对照：第一次 Login 200，第二次 409，exit 后再 Login 应 200。

console.log("[*] replace_newNonce.js loaded");

const FIXED_NONCE = "frida-fixed-nonce";
const retained = [];

function run() {
  if (!ObjC.available) {
    console.log("[-] ObjC.available = false");
    return;
  }

  const Signer = ObjC.classes.HMACSigner;
  if (Signer === undefined || Signer["+ newNonce"] === undefined) {
    console.log("[-] 没有 +[HMACSigner newNonce]");
    return;
  }

  Interceptor.attach(Signer["+ newNonce"].implementation, {
    onLeave: function (retval) {
      let original = "(unreadable)";
      try {
        original = new ObjC.Object(retval).toString();
      } catch (error) {
      }

      const replaced = ObjC.classes.NSString.alloc().initWithString_(FIXED_NONCE);
      replaced.retain();
      retained.push(replaced);
      retval.replace(replaced.handle);

      console.log("[+] +[HMACSigner newNonce]");
      console.log("    原返回值 = " + original);
      console.log("    改为     = " + FIXED_NONCE);
    }
  });

  console.log("[*] hooked +newNonce，返回值固定为 " + FIXED_NONCE);
  console.log("[*] 点两次 Login：第一次 200，第二次 409。然后 exit 恢复。");
}

setImmediate(run);
