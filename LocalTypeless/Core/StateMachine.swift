import Foundation
import Observation

@MainActor
@Observable
final class StateMachine {
    private(set) var state: DictationState = .idle

    func toggle() {
        switch state {
        case .idle:
            state = .recording
            Log.state.info("idle -> recording")
        case .recording:
            state = .transcribing
            Log.state.info("recording -> transcribing")
        case .error:
            state = .idle
            Log.state.info("error -> idle")
        case .transcribing, .polishing, .injecting:
            Log.state.debug("toggle ignored in \(String(describing: self.state), privacy: .public)")
        }
    }

    func advance() {
        switch state {
        case .transcribing:
            state = .polishing
            Log.state.info("transcribing -> polishing")
        case .polishing:
            state = .injecting
            Log.state.info("polishing -> injecting")
        case .injecting:
            state = .idle
            Log.state.info("injecting -> idle")
        default:
            Log.state.debug("advance ignored in \(String(describing: self.state), privacy: .public)")
        }
    }

    func startInjecting() {
        switch state {
        case .transcribing, .polishing:
            state = .injecting
            Log.state.info("processing -> injecting")
        default:
            Log.state.debug("startInjecting ignored in \(String(describing: self.state), privacy: .public)")
        }
    }

    func finish() {
        switch state {
        case .transcribing, .polishing, .injecting:
            state = .idle
            Log.state.info("processing -> idle")
        default:
            Log.state.debug("finish ignored in \(String(describing: self.state), privacy: .public)")
        }
    }

    func cancelRecording() {
        switch state {
        case .recording:
            state = .idle
            Log.state.info("recording -> idle")
        default:
            Log.state.debug("cancelRecording ignored in \(String(describing: self.state), privacy: .public)")
        }
    }

    func fail(message: String) {
        state = .error(message)
        Log.state.error("failed: \(message, privacy: .public)")
    }
}
