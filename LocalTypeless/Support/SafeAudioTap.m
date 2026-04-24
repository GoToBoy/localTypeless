#import "SafeAudioTap.h"

NSString * const SafeAudioTapErrorDomain = @"SafeAudioTapErrorDomain";

@implementation SafeAudioTap

+ (BOOL)installTapOn:(AVAudioNode *)node
                 bus:(AVAudioNodeBus)bus
          bufferSize:(AVAudioFrameCount)bufferSize
              format:(AVAudioFormat *)format
               block:(AVAudioNodeTapBlock)block
               error:(NSError * _Nullable * _Nullable)outError {
    @try {
        [node installTapOnBus:bus bufferSize:bufferSize format:format block:block];
        return YES;
    } @catch (NSException *exception) {
        // AVAudioEngine's internal validation raises NSException from C++
        // land — e.g. `required condition is false: nullptr == Tap()` or
        // `-10868 / Error, formats don't match`. Swift's `try`/`catch` can't
        // see those, so without this bridge the whole process gets SIGABRT'd.
        // Packaging the exception as an NSError lets Swift fall back to a
        // soft error UI instead of dying.
        if (outError) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name ?: @"installTap failed";
            info[@"SafeAudioTapExceptionName"] = exception.name ?: @"";
            if (exception.userInfo) {
                info[@"SafeAudioTapExceptionUserInfo"] = exception.userInfo;
            }
            *outError = [NSError errorWithDomain:SafeAudioTapErrorDomain
                                            code:-1
                                        userInfo:info];
        }
        return NO;
    }
}

@end
