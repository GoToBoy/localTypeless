import AVFoundation
import AppKit
import ApplicationServices
@preconcurrency import IOKit.hid

@MainActor
final class PermissionChecker {

    enum Status: Equatable {
        case granted
        case denied
        case notDetermined
    }

    enum Kind: String {
        case microphone
        case accessibility
        case inputMonitoring
    }

    var microphoneStatus: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:          return .granted
        case .denied, .restricted: return .denied
        case .notDetermined:       return .notDetermined
        @unknown default:          return .notDetermined
        }
    }

    var accessibilityStatus: Status {
        AXIsProcessTrusted() ? .granted : .denied
    }

    var inputMonitoringStatus: Status {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:  return .denied
        case kIOHIDAccessTypeUnknown: return .notDetermined
        default:                      return .notDetermined
        }
    }

    /// Triggers the permission prompt for microphone. Other two prompt on first use.
    func requestMicrophoneIfNeeded() async -> Status {
        if microphoneStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return microphoneStatus
    }

    static func systemSettingsURL(for kind: Kind) -> URL? {
        switch kind {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }

    static func openSystemSettings(for kind: Kind) {
        guard let url = systemSettingsURL(for: kind) else { return }
        NSWorkspace.shared.open(url)
    }
}
