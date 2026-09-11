//
//  PinningURLSessionDelegate.m
//  SignDemo
//

#import "PinningURLSessionDelegate.h"
#import "APIConfig.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

@implementation PinningURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    NSString *method = challenge.protectionSpace.authenticationMethod;
    if (![method isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }

    if (!self.pinningEnabled) {
        self.lastFailureReason = nil;
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }

    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    if (trust == NULL) {
        self.lastFailureReason = @"Pinning 失败：serverTrust 为空";
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    NSString *actual = [self leafCertificateSHA256:trust];
    NSString *expected = SignDemoPinnedCertSHA256.lowercaseString;
    NSString *host = challenge.protectionSpace.host ?: @"";

    if (actual.length == 0) {
        self.lastFailureReason = @"Pinning 失败：无法读取服务器证书";
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    if (![actual isEqualToString:expected]) {
        self.lastFailureReason =
            [NSString stringWithFormat:
             @"Pinning 失败：证书指纹不匹配（代理或错误的服务器证书）\n"
             @"host: %@\n"
             @"expected: %@\n"
             @"actual:   %@",
             host, expected, actual];
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    self.lastFailureReason = nil;
    NSURLCredential *credential = [NSURLCredential credentialForTrust:trust];
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

- (NSString *)leafCertificateSHA256:(SecTrustRef)trust {
    SecCertificateRef certificate = NULL;
    CFArrayRef chain = SecTrustCopyCertificateChain(trust);
    if (chain != NULL && CFArrayGetCount(chain) > 0) {
        certificate = (SecCertificateRef)CFArrayGetValueAtIndex(chain, 0);
    }

    if (certificate == NULL) {
        if (chain != NULL) {
            CFRelease(chain);
        }
        return @"";
    }

    NSData *der = CFBridgingRelease(SecCertificateCopyData(certificate));
    CFRelease(chain);
    if (der.length == 0) {
        return @"";
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(der.bytes, (CC_LONG)der.length, digest);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

@end
