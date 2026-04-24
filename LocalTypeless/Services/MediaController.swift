import Foundation
import Darwin

/// Pauses system media playback (Music, Spotify, browser tabs, etc.) during a
/// recording and resumes after, so the microphone doesn't capture playback.
///
/// Uses the private `MediaRemote.framework` via `dlsym`. The framework ships
/// with every macOS and has been stable for years, but is technically SPI —
/// we fail gracefully (do nothing) if any symbol is missing.
@MainActor
final class MediaController {

    private static let libraryPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    // Command ids from `MRMediaRemoteCommand` enum.
    private static let kMRPlay:  Int32 = 0
    private static let kMRPause: Int32 = 1

    private typealias SendCommand =
        @convention(c) (Int32, CFDictionary?) -> Void
    private typealias GetIsPlaying =
        @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    private let sendCommand: SendCommand?
    private let getIsPlaying: GetIsPlaying?
    private var didPause = false

    init() {
        guard let h = dlopen(Self.libraryPath, RTLD_LAZY) else {
            self.sendCommand = nil
            self.getIsPlaying = nil
            Log.state.warning("MediaRemote unavailable; media pause disabled")
            return
        }
        self.sendCommand = dlsym(h, "MRMediaRemoteSendCommand").map {
            unsafeBitCast($0, to: SendCommand.self)
        }
        self.getIsPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying").map {
            unsafeBitCast($0, to: GetIsPlaying.self)
        }
    }

    /// Pause now-playing if it's currently playing. Records whether we paused
    /// so `resumeIfPaused()` only fires when we were the cause.
    func pauseIfPlaying() async {
        guard let sendCommand, let getIsPlaying else { return }
        let playing: Bool = await withCheckedContinuation { cont in
            getIsPlaying(.main) { isPlaying in
                cont.resume(returning: isPlaying)
            }
        }
        guard playing else { return }
        sendCommand(Self.kMRPause, nil)
        didPause = true
        Log.state.info("media paused for recording")
    }

    /// Resume only if `pauseIfPlaying()` actually paused something.
    func resumeIfPaused() {
        guard let sendCommand else { return }
        guard didPause else { return }
        didPause = false
        sendCommand(Self.kMRPlay, nil)
        Log.state.info("media resumed after recording")
    }
}
