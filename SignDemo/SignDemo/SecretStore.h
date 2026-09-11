//
//  SecretStore.h
//  SignDemo
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SecretStore : NSObject

+ (NSString *)obfuscatedSecret;
+ (NSString *)currentSecret;

@end

NS_ASSUME_NONNULL_END
