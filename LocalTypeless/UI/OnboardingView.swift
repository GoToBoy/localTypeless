import AppKit
import SwiftUI

struct OnboardingView: View {

    let checker: any PermissionCheckerProtocol
    let onContinue: () -> Void

    @State private var refreshTick: Int = 0  // bump to re-read permission status
    // Poll while the window is visible so status updates without a manual click
    // after the user grants a permission in System Settings.
    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var canContinue: Bool {
        checker.microphoneStatus == .granted
            && checker.inputMonitoringStatus == .granted
    }

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
                    revealAppInFinder()
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
                    revealAppInFinder()
                    PermissionChecker.openSystemSettings(for: .accessibility)
                }
            )

            // The built .app lives deep under DerivedData, so System
            // Settings' default file picker (rooted at /Applications) can't
            // find it. `revealAppInFinder` surfaces the bundle in Finder so
            // the user can drag it into the "+" sheet instead of navigating.
            Text(String(localized: "If System Settings can't find the app when you click +, drag this app's icon from Finder into the permissions list."))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(String(localized: "Show app in Finder"), action: revealAppInFinder)
                Text(Bundle.main.bundleURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 20)

            // Dev builds are ad-hoc signed, so every rebuild produces a new
            // code-directory hash — macOS TCC treats the new build as a
            // different app and orphans prior grants. The toggle the user
            // flips in System Settings may attach to the stale entry, not
            // this build. "Reset permissions" wipes all TCC entries for this
            // bundle ID so the next grant binds to the running build.
            Text(String(localized: "Dev builds change identity on every rebuild, which can orphan your previous grants. If permissions stay denied after enabling them, reset and grant again, then quit & relaunch."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(String(localized: "Reset permissions"), action: resetTCCEntries)
                Button(String(localized: "Quit & Relaunch"), action: relaunchApp)
                Spacer()
                Button(String(localized: "Refresh")) { refreshTick += 1 }
                Button(String(localized: "Continue"), action: onContinue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
        .padding(32)
        .frame(width: 560, height: 560)
        .id(refreshTick) // force re-read of computed properties on each tick
        .onReceive(pollTimer) { _ in refreshTick += 1 }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in refreshTick += 1 }
    }

    /// Opens Finder with the app bundle selected so the user can drag it
    /// into System Settings' permission picker. The built bundle lives
    /// under `~/Library/Developer/Xcode/DerivedData/…` which the default
    /// `/Applications/`-rooted picker cannot reach without navigation.
    private func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    /// Runs `tccutil reset All <bundle-id>` to purge stale permission grants
    /// left behind by prior ad-hoc-signed builds. macOS TCC binds grants to
    /// the app's code-directory hash, so a rebuild can render previous
    /// toggles useless — the entry the user sees in System Settings may
    /// belong to an older cdhash that's no longer this process.
    private func resetTCCEntries() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.localtypeless.LocalTypeless"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "All", bundleID]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Log.state.error("tccutil reset failed: \(String(describing: error), privacy: .public)")
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Permissions reset")
        alert.informativeText = String(localized: "All permission grants for this app have been cleared. Grant them again from the rows above, then click Quit & Relaunch.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
        refreshTick += 1
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
