#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C bridge around -[AVAudioNode installTapOnBus:…] that catches
/// the `NSException` AVAudioEngine raises when the input graph can't be
/// initialized.
///
/// Why this exists: `installTap` validates the input chain internally at
/// call time. If the default input device is missing or has no input
/// streams (e.g. user's output-only AirPods are the "default input" —
/// macOS will report Input:No when listing the device), that validation
/// raises
///     required condition is false: nullptr == Tap()
/// or
///     -10868 / Error, formats don't match
/// as `NSException`, which Swift's `try`/`catch` cannot intercept. Without
/// this shim the process is torn down by SIGABRT. With it, Swift gets a
/// conventional `NSError` and can fall back to a soft error UI instead of
/// taking the whole app with it.
@interface SafeAudioTap : NSObject

+ (BOOL)installTapOn:(AVAudioNode *)node
                 bus:(AVAudioNodeBus)bus
          bufferSize:(AVAudioFrameCount)bufferSize
              format:(nullable AVAudioFormat *)format
               block:(AVAudioNodeTapBlock)block
               error:(NSError * _Nullable * _Nullable)outError;

@end

NS_ASSUME_NONNULL_END
