#import "MMBundleSoundFiles.h"

#if __has_include(<MessEngine/MessEngine.h>)

@implementation MMBundleSoundFiles

+ (nullable NSData *)dataForPath:(NSString *)path {
    if ([path hasPrefix:@"/"]) {
        NSString *full = [path stringByStandardizingPath];
        NSString *home = [NSHomeDirectory() stringByAppendingString:@"/"];
        NSString *bundle = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/"];
        if (![full hasPrefix:home] && ![full hasPrefix:bundle]) return nil;
        return [NSData dataWithContentsOfFile:full];
    }
    NSString *p = path;
    if ([p hasPrefix:@"sounds/"]) p = [p substringFromIndex:7];
    if (p.length == 0 || [[p componentsSeparatedByString:@"/"] containsObject:@".."]) return nil;
    NSString *root = [[NSBundle mainBundle] pathForResource:@"sounds" ofType:nil];
    if (!root) return nil;
    return [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:p]];
}

- (MessEngineKotlinByteArray * _Nullable)readPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error {
    NSData *d = [MMBundleSoundFiles dataForPath:path];
    if (!d) return nil;
    NSUInteger n = d.length;
    MessEngineKotlinByteArray *a = [MessEngineKotlinByteArray arrayWithSize:(int32_t)n];
    const int8_t *b = (const int8_t *)d.bytes;
    for (NSUInteger i = 0; i < n; i++) [a setIndex:(int32_t)i value:b[i]];
    return a;
}

@end
#endif
