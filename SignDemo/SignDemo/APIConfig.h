//
//  APIConfig.h
//  SignDemo
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// XR 真机必须填 Mac 局域网 IP。127.0.0.1 在手机上指向 XR 自己，不是 Mac。
FOUNDATION_EXPORT NSString * const SignDemoDefaultBaseURL;
FOUNDATION_EXPORT NSString * const SignDemoSigningSecret;
FOUNDATION_EXPORT NSString * const SignDemoDefaultUserID;
FOUNDATION_EXPORT NSString * const SignDemoDefaultPassword;
FOUNDATION_EXPORT NSString * const SignDemoDefaultOrderID;
FOUNDATION_EXPORT const NSInteger SignDemoDefaultOrderAmount;

/// 打开后只接受指纹匹配的服务器证书。关掉则走系统 CA 信任。
FOUNDATION_EXPORT BOOL SignDemoPinningEnabled;
FOUNDATION_EXPORT NSString * const SignDemoPinnedCertSHA256;

/// 简单反调试，默认关闭。打开后只提示，不 exit。
FOUNDATION_EXPORT BOOL SignDemoAntiDebugEnabled;

/// 打开则使用字面量 SignDemoSigningSecret，关闭则走 XOR 还原。默认关。
FOUNDATION_EXPORT BOOL SignDemoUsePlainSecret;

NS_ASSUME_NONNULL_END
