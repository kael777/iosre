// SignDemo W11：只读抓 HMAC 的 message / secret / digest。
// 不改返回值。明文 secret 开关请先关掉，确认 XOR 还原结果。
//
//   frida -U -n SignDemo \
//     -l /Users/weideshun/Desktop/SignDemo/scripts/frida/capture_hmac_input.js

console.log("[*] capture_hmac_input.js loaded");

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

function run() {
  if (!ObjC.available) {
    console.log("[-] ObjC.available = false");
    return;
  }

  const Signer = ObjC.classes.HMACSigner;
  const sel = "+ hexHMACSHA256WithMessage:secret:";
  if (Signer === undefined || Signer[sel] === undefined) {
    console.log("[-] 没有 " + sel);
    return;
  }

  Interceptor.attach(Signer[sel].implementation, {
    onEnter: function (args) {
      this.message = safeStr(args[2]);
      this.secret = safeStr(args[3]);
    },
    onLeave: function (retval) {
      console.log("[+] +[HMACSigner hexHMACSHA256WithMessage:secret:]");
      console.log("    message (canonical) = " + this.message);
      console.log("    secret              = " + this.secret);
      console.log("    digest (sign)       = " + safeStr(retval));
    }
  });
  console.log("[*] hooked " + sel);
  console.log("[*] 关掉「明文 secret」，点 Login。secret 应仍是 local-demo-secret-v1");
}

setImmediate(run);
