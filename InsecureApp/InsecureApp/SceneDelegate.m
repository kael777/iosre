#import "SceneDelegate.h"
#import "AppDelegate.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    for (UIOpenURLContext *ctx in connectionOptions.URLContexts) {
        [self openURL:ctx.URL];
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    for (UIOpenURLContext *ctx in URLContexts) {
        [self openURL:ctx.URL];
    }
}

- (void)openURL:(NSURL *)url {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([app respondsToSelector:@selector(handleInboundURL:)]) {
        [app handleInboundURL:url];
    }
}

@end
