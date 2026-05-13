import Foundation
@preconcurrency import ApplicationServices
@preconcurrency import AppKit
import Carbon.HIToolbox

/// Strategy used to paste the transcribed text into the focused app after
/// staging it on the pasteboard.
enum PasteMethod: String, Codable, CaseIterable, Sendable {
    /// Synthesize ⌘V via `CGEvent` at the HID tap. Lowest latency, but some
    /// exotic keyboard layouts (e.g. "X – QWERTY ⌘") rewrite Command-layer
    /// keys; we work around that by posting the physical V key code.
    case cgEvent
    /// Ask `System Events` to keystroke ⌘V. Requires Automation permission
    /// but dodges CGEvent quirks and survives apps that filter synthesized
    /// HID events.
    case appleScript
}

@MainActor
class TextInjector {

    struct Target: Equatable, Sendable {
        var processIdentifier: pid_t?
        var bundleIdentifier: String?
    }

    struct Options: Equatable {
        var pasteMethod: PasteMethod = .cgEvent
        /// Save the current pasteboard string before pasting and restore it
        /// shortly after. Off means we leave the transcribed text on the
        /// pasteboard, which is easier to recover manually but clobbers the
        /// user's clipboard.
        var preserveClipboard: Bool = true
    }

    enum InjectionError: Error, Equatable {
        case accessibilityDenied
        case noFocusedWindow
        case eventCreationFailed
        case appleScriptFailed(String)
        case pasteFailed(String)
    }

    struct PasteboardSnapshot {
        struct Item {
            let payloads: [(type: NSPasteboard.PasteboardType, data: Data)]
        }

        let items: [Item]
    }

    var options: Options = .init()

    func inject(_ text: String, target: Target? = nil) async throws {
        guard !text.isEmpty else { return }

        let pb = NSPasteboard.general
        let snapshot = options.preserveClipboard
            ? Self.capturePasteboard(pb)
            : nil
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            Log.injector.warning("accessibility not trusted — leaving text on pasteboard")
            throw InjectionError.accessibilityDenied
        }

        let app = resolveTargetApplication(target)
        guard let app, await activateTargetApplication(app) else {
            Log.injector.warning("no focused target window — leaving text on pasteboard")
            throw InjectionError.noFocusedWindow
        }
        if !hasFocusedWindow(in: app) {
            Log.injector.warning("target app is active but AX focused window was unavailable; attempting paste anyway")
        }

        switch options.pasteMethod {
        case .cgEvent:
            try postCommandV()
        case .appleScript:
            try pasteViaAppleScript()
        }

        // wait for the target app to consume ⌘V before restoring
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if let snapshot {
            Self.restorePasteboard(pb, snapshot: snapshot)
        }
        Log.injector.info("injected \(text.count, privacy: .public) chars via \(self.options.pasteMethod.rawValue, privacy: .public)")
    }

    static func capturePasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let payloads: [(type: NSPasteboard.PasteboardType, data: Data)] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type: type, data: data)
            }
            return PasteboardSnapshot.Item(payloads: payloads)
        }
        return PasteboardSnapshot(items: items)
    }

    static func restorePasteboard(_ pasteboard: NSPasteboard, snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let restoredItems = snapshot.items.map { snapshotItem in
            let item = NSPasteboardItem()
            for payload in snapshotItem.payloads {
                item.setData(payload.data, forType: payload.type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }

    /// Post ⌘V at the HID event tap using the physical V key code (9). Using
    /// the physical key code — rather than character "V" — avoids layouts
    /// that remap QWERTY under ⌘, e.g. "X – QWERTY ⌘" which otherwise
    /// produces a paste of the wrong character.
    private func postCommandV() throws {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)   // == 9
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else {
            throw InjectionError.eventCreationFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func pasteViaAppleScript() throws {
        let source = #"""
        tell application "System Events" to keystroke "v" using command down
        """#
        guard let script = NSAppleScript(source: source) else {
            Log.injector.error("applescript compile failed")
            throw InjectionError.appleScriptFailed("compile failed")
        }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if let err {
            Log.injector.error("applescript paste failed: \(String(describing: err), privacy: .public)")
            throw InjectionError.appleScriptFailed(String(describing: err))
        }
    }

    private func resolveTargetApplication(_ target: Target?) -> NSRunningApplication? {
        if let processIdentifier = target?.processIdentifier,
           let app = NSRunningApplication(processIdentifier: processIdentifier),
           isPasteTargetCandidate(app) {
            return app
        }
        if let bundleIdentifier = target?.bundleIdentifier {
            return NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first { isPasteTargetCandidate($0) }
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              isPasteTargetCandidate(app) else {
            return nil
        }
        return app
    }

    private func activateTargetApplication(_ app: NSRunningApplication?) async -> Bool {
        guard let app else { return false }
        if isFrontmost(app) { return true }
        app.unhide()
        _ = app.activate(options: [])
        for attempt in 0..<12 {
            if isFrontmost(app) || app.isActive {
                return true
            }
            if attempt == 3 {
                await activateViaWorkspace(app)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return isFrontmost(app) || app.isActive
    }

    private func activateViaWorkspace(_ app: NSRunningApplication) async {
        guard let bundleURL = app.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                if let error {
                    Log.injector.error("workspace activation failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    private func isPasteTargetCandidate(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated else { return false }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }
        return app.activationPolicy == .regular
    }

    private func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private func hasFocusedWindow(in app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        if attributeExists(kAXFocusedWindowAttribute, on: axApp) {
            return true
        }
        if attributeExists(kAXMainWindowAttribute, on: axApp) {
            return true
        }
        if attributeExists(kAXFocusedUIElementAttribute, on: axApp) {
            return true
        }

        return false
    }

    private func attributeExists(_ attribute: String, on element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        return result == .success && value != nil
    }
}
