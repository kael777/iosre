#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const InsecureAppSessionDidChangeNotification;

@interface Session : NSObject

@property (nonatomic, assign) BOOL authenticated;
@property (nonatomic, copy) NSString *source;

+ (instancetype)shared;
- (void)loginWithSource:(NSString *)source;
- (void)logout;

@end

NS_ASSUME_NONNULL_END
