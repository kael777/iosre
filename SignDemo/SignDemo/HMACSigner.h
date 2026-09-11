//
//  HMACSigner.h
//  SignDemo
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HMACSigner : NSObject

+ (NSString *)canonicalStringWithUserID:(NSString *)userID
                              timestamp:(long long)timestamp
                                  nonce:(NSString *)nonce
                                 action:(NSString *)action;

+ (NSString *)hexHMACSHA256WithMessage:(NSString *)message
                                secret:(NSString *)secret;

+ (NSString *)signWithUserID:(NSString *)userID
                   timestamp:(long long)timestamp
                       nonce:(NSString *)nonce
                      action:(NSString *)action
                      secret:(NSString *)secret;

+ (NSString *)newNonce;

@end

NS_ASSUME_NONNULL_END
