//
//  AntiDebug.m
//  SignDemo
//
//  W6 第一版：只检测，不 ptrace、不 exit。
//

#import "AntiDebug.h"

#include <string.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef P_TRACED
#define P_TRACED 0x00000800
#endif

@implementation AntiDebug

+ (BOOL)hasPTracedFlag {
    int names[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    size_t size = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (sysctl(names, 4, &info, &size, NULL, 0) != 0) {
        return NO;
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

+ (BOOL)parentLooksUnusual {
    pid_t parent = getppid();
    return parent > 1;
}

+ (BOOL)stdioLooksLikeTerminal {
    return isatty(STDIN_FILENO) || isatty(STDOUT_FILENO);
}

+ (BOOL)isBeingTraced {
    // getppid 在越狱设备上不一定是 1，只展示不作为判定。
    return [self hasPTracedFlag] || [self stdioLooksLikeTerminal];
}

+ (NSString *)statusSummary {
    return [NSString stringWithFormat:
            @"P_TRACED=%@  getppid=%d  isatty=%@",
            [self hasPTracedFlag] ? @"YES" : @"NO",
            getppid(),
            [self stdioLooksLikeTerminal] ? @"YES" : @"NO"];
}

@end
