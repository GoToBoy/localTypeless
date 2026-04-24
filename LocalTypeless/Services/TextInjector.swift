import Foundation
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

    struct Options: Equatable {
        var pasteMethod: PasteMethod = .cgEvent
        /// Save the current pasteboard string before pasting and restore it
        /// shortly after. Off means we leave the transcribed text on the
        /// pasteboard, which is easier to recover manually but clobbers the
        /// user's clipboard.
        var preserveClipboard: Bool = true
    }

    enum InjectionError: Error {
        case accessibilityDenied
    }

    var options: Options = .init()

    func inject(_ text: String) async throws {
        let pb = NSPasteboard.general
        let previous = options.preserveClipboard
            ? pb.pasteboardItems?.first?.string(forType: .string)
            : nil
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            Log.injector.warning("accessibility not trusted — leaving text on pasteboard")
            throw InjectionError.accessibilityDenied
        }

        switch options.pasteMethod {
        case .cgEvent:
            postCommandV()
        case .appleScript:
            pasteViaAppleScript()
        }

        // wait for the target app to consume ⌘V before restoring
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
        Log.injector.info("injected \(text.count, privacy: .public) chars via \(self.options.pasteMethod.rawValue, privacy: .public)")
    }

    /// Post ⌘V at the HID event tap using the physical V key code (9). Using
    /// the physical key code — rather than character "V" — avoids layouts
    /// that remap QWERTY under ⌘, e.g. "X – QWERTY ⌘" which otherwise
    /// produces a paste of the wrong character.
    private func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)   // == 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func pasteViaAppleScript() {
        let source = #"""
        tell application "System Events" to keystroke "v" using command down
        """#
        guard let script = NSAppleScript(source: source) else {
            Log.injector.error("applescript compile failed")
            return
        }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if let err {
            Log.injector.error("applescript paste failed: \(String(describing: err), privacy: .public)")
        }
    }
}
