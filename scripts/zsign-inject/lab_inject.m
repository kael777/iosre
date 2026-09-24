// zsign -l 实验：App 启动时 constructor 会跑。
// 只做可见性验证，不 hook、不改业务。
#import <Foundation/Foundation.h>
#include <unistd.h>

__attribute__((constructor))
static void lab_inject_init(void) {
    NSLog(@"[zsign-lab] dylib loaded pid=%d", getpid());
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (dir.length == 0) {
        return;
    }
    NSString *path = [dir stringByAppendingPathComponent:@"zsign_lab_inject.txt"];
    NSString *line = [NSString stringWithFormat:@"loaded %@\n", [NSDate date]];
    [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
