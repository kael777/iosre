//
//  APIConfig.m
//  SignDemo
//

#import "APIConfig.h"

// 当前 Mac 局域网地址来自 en1：ipconfig getifaddr en1
// W4 默认走 HTTPS :5443。换网络后改这里，或在输入框里临时覆盖。
NSString * const SignDemoDefaultBaseURL = @"https://192.168.1.8:5443";
NSString * const SignDemoSigningSecret = @"local-demo-secret-v1";
NSString * const SignDemoDefaultUserID = @"demo-user-001";
NSString * const SignDemoDefaultPassword = @"demo-password";
NSString * const SignDemoDefaultOrderID = @"order-001";
const NSInteger SignDemoDefaultOrderAmount = 10;

// 来自：openssl x509 -in backend/certs/server.crt -outform DER | shasum -a 256
// 重签证书后必须改这一行。
BOOL SignDemoPinningEnabled = YES;
NSString * const SignDemoPinnedCertSHA256 =
    @"ff85926af95e4574fbb47e19ffd4ad6ce90dfb6012d84e0effb995904dd377ce";
BOOL SignDemoAntiDebugEnabled = NO;
BOOL SignDemoUsePlainSecret = NO;
