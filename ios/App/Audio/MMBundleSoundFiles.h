// The shared engine's SoundFiles over the app bundle, in Objective-C: Kotlin's read(path) may both throw and return
// nothing, which Swift cannot implement for an Objective-C protocol (Swift reads a nil return as an error).
#import <Foundation/Foundation.h>

#if __has_include(<MessMachine/MessMachine.h>)
#import <MessMachine/MessMachine.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads "sounds/..." (or "loops/x.flac") from the bundled sounds/ folder, and full paths only inside the app's own
/// container. Returns nil, with no error, when there is no such file.
@interface MMBundleSoundFiles : NSObject <MessMachineSoundFiles>
+ (nullable NSData *)dataForPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
#endif
