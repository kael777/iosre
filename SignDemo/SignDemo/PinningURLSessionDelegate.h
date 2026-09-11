//
//  PinningURLSessionDelegate.h
//  SignDemo
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PinningURLSessionDelegate : NSObject <NSURLSessionDelegate>

@property (nonatomic, assign) BOOL pinningEnabled;
@property (nonatomic, copy, nullable) NSString *lastFailureReason;

@end

NS_ASSUME_NONNULL_END
