import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static func apply(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, .notRegistered), (true, .notFound):
            try service.register()
        case (false, .enabled), (false, .requiresApproval):
            try service.unregister()
        default:
            break
        }
    }

    static func applySilently(_ enabled: Bool) {
        do {
            try apply(enabled)
        } catch {
            Log.state.error("launch-at-login toggle failed: \(String(describing: error), privacy: .public)")
        }
    }
}
