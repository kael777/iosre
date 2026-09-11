//
//  AntiDebug.h
//  SignDemo
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AntiDebug : NSObject

+ (BOOL)isBeingTraced;
+ (NSString *)statusSummary;

@end

NS_ASSUME_NONNULL_END
