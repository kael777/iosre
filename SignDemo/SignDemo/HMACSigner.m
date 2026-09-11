//
//  HMACSigner.m
//  SignDemo
//

#import "HMACSigner.h"
#import <CommonCrypto/CommonHMAC.h>

@implementation HMACSigner

+ (NSString *)canonicalStringWithUserID:(NSString *)userID
                              timestamp:(long long)timestamp
                                  nonce:(NSString *)nonce
                                 action:(NSString *)action {
    return [NSString stringWithFormat:
            @"user_id=%@&timestamp=%lld&nonce=%@&action=%@",
            userID ?: @"",
            timestamp,
            nonce ?: @"",
            action ?: @""];
}

+ (NSString *)hexHMACSHA256WithMessage:(NSString *)message
                                secret:(NSString *)secret {
    NSData *keyData = [secret dataUsingEncoding:NSUTF8StringEncoding];
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];

    CCHmac(
        kCCHmacAlgSHA256,
        keyData.bytes,
        keyData.length,
        messageData.bytes,
        messageData.length,
        digest
    );

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

+ (NSString *)signWithUserID:(NSString *)userID
                   timestamp:(long long)timestamp
                       nonce:(NSString *)nonce
                      action:(NSString *)action
                      secret:(NSString *)secret {
    NSString *canonical = [self canonicalStringWithUserID:userID
                                                timestamp:timestamp
                                                    nonce:nonce
                                                   action:action];
    return [self hexHMACSHA256WithMessage:canonical secret:secret];
}

+ (NSString *)newNonce {
    return [NSString stringWithFormat:@"%08x%08x", arc4random(), arc4random()];
}

@end
