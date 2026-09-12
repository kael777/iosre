//
//  JailbreakCheck.m
//  SignDemo
//
//  W19 执行 4：路径按字节 XOR 0x5A，运行时还原再 fileExistsAtPath:。
//  混淆的是字面量，不是算法。Frida hook 仍能看到还原后的 path。
//

#import "JailbreakCheck.h"

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>

static const unsigned char kXorKey = 0x5A;

static const unsigned char kPathCydia[] = {
    0x75, 0x1b, 0x2a, 0x2a, 0x36, 0x33, 0x39, 0x3b, 0x2e, 0x33, 0x35, 0x34,
    0x29, 0x75, 0x19, 0x23, 0x3e, 0x33, 0x3b, 0x74, 0x3b, 0x2a, 0x2a
};
static const unsigned char kPathSubstrate[] = {
    0x75, 0x16, 0x33, 0x38, 0x28, 0x3b, 0x28, 0x23, 0x75, 0x17, 0x35, 0x38,
    0x33, 0x36, 0x3f, 0x09, 0x2f, 0x38, 0x29, 0x2e, 0x28, 0x3b, 0x2e, 0x3f,
    0x75, 0x17, 0x35, 0x38, 0x33, 0x36, 0x3f, 0x09, 0x2f, 0x38, 0x29, 0x2e,
    0x28, 0x3b, 0x2e, 0x3f, 0x74, 0x3e, 0x23, 0x36, 0x33, 0x38
};
static const unsigned char kPathVarjb[] = {
    0x75, 0x2c, 0x3b, 0x28, 0x75, 0x30, 0x38
};
static const unsigned char kPathSshd[] = {
    0x75, 0x2c, 0x3b, 0x28, 0x75, 0x30, 0x38, 0x75, 0x2f, 0x29, 0x28, 0x75,
    0x29, 0x38, 0x33, 0x34, 0x75, 0x29, 0x29, 0x32, 0x3e
};
static const unsigned char kPathSileoApp[] = {
    0x75, 0x2c, 0x3b, 0x28, 0x75, 0x30, 0x38, 0x75, 0x1b, 0x2a, 0x2a, 0x36,
    0x33, 0x39, 0x3b, 0x2e, 0x33, 0x35, 0x34, 0x29, 0x75, 0x09, 0x33, 0x36,
    0x3f, 0x35, 0x74, 0x3b, 0x2a, 0x2a
};

@implementation JailbreakCheck

+ (NSString *)decodeBytes:(const unsigned char *)bytes length:(NSUInteger)length {
    unsigned char *plain = malloc(length);
    if (plain == NULL) {
        return @"";
    }
    for (NSUInteger i = 0; i < length; i++) {
        plain[i] = (unsigned char)(bytes[i] ^ kXorKey);
    }
    NSString *decoded = [[NSString alloc] initWithBytes:plain
                                                 length:length
                                               encoding:NSUTF8StringEncoding];
    memset(plain, 0, length);
    free(plain);
    return decoded ?: @"";
}

+ (BOOL)fileExists:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (BOOL)canOpenScheme:(NSString *)scheme {
    NSURL *url = [NSURL URLWithString:[scheme stringByAppendingString:@"://"]];
    if (url == nil) {
        return NO;
    }
    return [[UIApplication sharedApplication] canOpenURL:url];
}

+ (NSString *)yesNo:(BOOL)value {
    return value ? @"YES" : @"NO";
}

+ (NSString *)fileLine {
    NSString *cydia = [self decodeBytes:kPathCydia length:sizeof(kPathCydia)];
    NSString *substrate = [self decodeBytes:kPathSubstrate length:sizeof(kPathSubstrate)];
    NSString *varjb = [self decodeBytes:kPathVarjb length:sizeof(kPathVarjb)];
    NSString *sshd = [self decodeBytes:kPathSshd length:sizeof(kPathSshd)];
    NSString *sileoApp = [self decodeBytes:kPathSileoApp length:sizeof(kPathSileoApp)];
    return [NSString stringWithFormat:
            @"file: cydiaApp=%@ substrate=%@ varjb=%@ sshd=%@ sileoApp=%@",
            [self yesNo:[self fileExists:cydia]],
            [self yesNo:[self fileExists:substrate]],
            [self yesNo:[self fileExists:varjb]],
            [self yesNo:[self fileExists:sshd]],
            [self yesNo:[self fileExists:sileoApp]]];
}

+ (NSString *)schemeLine {
    return [NSString stringWithFormat:
            @"scheme: cydia=%@ sileo=%@ filza=%@",
            [self yesNo:[self canOpenScheme:@"cydia"]],
            [self yesNo:[self canOpenScheme:@"sileo"]],
            [self yesNo:[self canOpenScheme:@"filza"]]];
}

+ (BOOL)imageNameContains:(NSString *)needle {
    NSString *target = needle.lowercaseString;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name == NULL) {
            continue;
        }
        NSString *image = [NSString stringWithUTF8String:name].lowercaseString;
        if ([image containsString:target]) {
            return YES;
        }
    }
    return NO;
}

+ (NSString *)imageLine {
    const char *inserted = getenv("DYLD_INSERT_LIBRARIES");
    NSString *dyld = (inserted == NULL || inserted[0] == '\0')
        ? @"(null)"
        : [NSString stringWithUTF8String:inserted];
    return [NSString stringWithFormat:
            @"image: DYLD_INSERT=%@ frida=%@ ellekit=%@ TweakInject=%@ substrate=%@",
            dyld,
            [self yesNo:[self imageNameContains:@"frida"]],
            [self yesNo:[self imageNameContains:@"ellekit"]],
            [self yesNo:[self imageNameContains:@"tweakinject"]],
            [self yesNo:[self imageNameContains:@"substrate"]]];
}

+ (NSString *)statusSummary {
    return [NSString stringWithFormat:@"%@\n%@\n%@",
            [self fileLine],
            [self schemeLine],
            [self imageLine]];
}

@end
