#import "Session.h"

NSNotificationName const InsecureAppSessionDidChangeNotification = @"InsecureAppSessionDidChangeNotification";

@implementation Session

+ (instancetype)shared {
    static Session *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        session = [[Session alloc] init];
        session.source = @"none";
    });
    return session;
}

- (void)loginWithSource:(NSString *)source {
    self.authenticated = YES;
    self.source = source ?: @"unknown";
    [[NSNotificationCenter defaultCenter] postNotificationName:InsecureAppSessionDidChangeNotification
                                                        object:self];
}

- (void)logout {
    self.authenticated = NO;
    self.source = @"none";
    [[NSNotificationCenter defaultCenter] postNotificationName:InsecureAppSessionDidChangeNotification
                                                        object:self];
}

@end
