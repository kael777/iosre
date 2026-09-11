#import "AppDelegate.h"
#import "Session.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                             options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                          sessionRole:connectingSceneSession.role];
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    [self handleInboundURL:url];
    return YES;
}

- (void)handleInboundURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"insecureapp"]) {
        return;
    }
    NSLog(@"ignored inbound URL (W16 fix): %@", url.absoluteString);
}

@end
