//
//  SecretStore.m
//  SignDemo
//
//  W11：明文拆成两段，每字节 XOR 0x5A。最终仍是 local-demo-secret-v1。
//

#import "SecretStore.h"
#import "APIConfig.h"

static const unsigned char kXorKey = 0x5A;
static const unsigned char kPartA[] = {
    0x36, 0x35, 0x39, 0x3b, 0x36, 0x77, 0x3e, 0x3f, 0x37, 0x35
};
static const unsigned char kPartB[] = {
    0x77, 0x29, 0x3f, 0x39, 0x28, 0x3f, 0x2e, 0x77, 0x2c, 0x6b
};

@implementation SecretStore

+ (NSString *)obfuscatedSecret {
    unsigned char bytes[sizeof(kPartA) + sizeof(kPartB)];
    for (size_t i = 0; i < sizeof(kPartA); i++) {
        bytes[i] = (unsigned char)(kPartA[i] ^ kXorKey);
    }
    for (size_t i = 0; i < sizeof(kPartB); i++) {
        bytes[sizeof(kPartA) + i] = (unsigned char)(kPartB[i] ^ kXorKey);
    }
    return [[NSString alloc] initWithBytes:bytes
                                    length:sizeof(bytes)
                                  encoding:NSUTF8StringEncoding];
}

+ (NSString *)currentSecret {
    if (SignDemoUsePlainSecret) {
        return SignDemoSigningSecret;
    }
    return [self obfuscatedSecret];
}

@end
