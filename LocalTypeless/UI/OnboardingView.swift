import SwiftUI

struct OnboardingView: View {

    let checker: PermissionChecker
    let onContinue: () -> Void

    @State private var refreshTick: Int = 0  // bump to re-read permission status

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "Welcome to local-typeless"))
                .font(.title)
                .fontWeight(.semibold)
            Text(String(localized: "Grant three permissions so we can record, listen for the hotkey, and paste the polished text."))
                .foregroundStyle(.secondary)

            Divider()

            permissionRow(
                title: String(localized: "Microphone"),
                subtitle: String(localized: "Required to record audio"),
                systemImage: "mic.fill",
                status: checker.microphoneStatus,
                kind: .microphone,
                action: {
                    Task { @MainActor in
                        _ = await checker.requestMicrophoneIfNeeded()
                        refreshTick += 1
                    }
                }
            )
            permissionRow(
                title: String(localized: "Input Monitoring"),
                subtitle: String(localized: "Required to listen for the global hotkey"),
                systemImage: "keyboard",
                status: checker.inputMonitoringStatus,
                kind: .inputMonitoring,
                action: {
                    PermissionChecker.openSystemSettings(for: .inputMonitoring)
                }
            )
            permissionRow(
                title: String(localized: "Accessibility"),
                subtitle: String(localized: "Paste polished text into other apps (optional — clipboard fallback)"),
                systemImage: "hand.point.up.left.fill",
                status: checker.accessibilityStatus,
                kind: .accessibility,
                action: {
                    PermissionChecker.openSystemSettings(for: .accessibility)
                }
            )

            Spacer(minLength: 20)

            HStack {
                Spacer()
                Button(String(localized: "Refresh")) { refreshTick += 1 }
                Button(String(localized: "Continue"), action: onContinue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checker.microphoneStatus != .granted)
            }
        }
        .padding(32)
        .frame(width: 560, height: 480)
        .id(refreshTick) // force re-read of computed properties on each tick
    }

    @ViewBuilder
    private func permissionRow(
        title: String, subtitle: String, systemImage: String,
        status: PermissionChecker.Status, kind: PermissionChecker.Kind,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            Image(systemName: systemImage)
                .frame(width: 36, height: 36)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(status)
            Button(status == .granted ? String(localized: "Granted") : String(localized: "Grant"),
                   action: action)
                .disabled(status == .granted)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionChecker.Status) -> some View {
        switch status {
        case .granted:
            Label(String(localized: "Granted"), systemImage: "checkmark.seal.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
        case .denied:
            Label(String(localized: "Denied"), systemImage: "xmark.seal.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        case .notDetermined:
            Label(String(localized: "Not set"), systemImage: "questionmark.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
    }
}
