import Foundation
@preconcurrency import AppKit

@MainActor
final class TextInjector {

    enum InjectionError: Error {
        case accessibilityDenied
    }

    private struct PasteboardSnapshot {
        struct Item {
            let payloads: [(type: NSPasteboard.PasteboardType, data: Data)]
        }

        let items: [Item]
    }

    func inject(_ text: String) async throws {
        // BUG-F03: empty transcript must never reach the pasteboard or synthesise
        // a Cmd+V — doing so would silently clear the user's clipboard and paste
        // nothing into the focused app.
        guard !text.isEmpty else {
            Log.injector.info("skip injection: empty text")
            return
        }

        let pb = NSPasteboard.general

        // Snapshot every pasteboard item so restoration preserves empty,
        // single-item, and multi-item clipboards.
        let snapshot = capturePasteboard(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            Log.injector.warning("accessibility not trusted — leaving text on pasteboard")
            throw InjectionError.accessibilityDenied
        }

        postCommandV()

        // wait for the target app to consume Cmd+V before restoring
        try? await Task.sleep(nanoseconds: 300_000_000)
        restorePasteboard(pb, snapshot: snapshot)
        Log.injector.info("injected \(text.count, privacy: .public) chars")
    }

    private func capturePasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let payloads: [(type: NSPasteboard.PasteboardType, data: Data)] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type: type, data: data)
            }
            return PasteboardSnapshot.Item(payloads: payloads)
        }
        return PasteboardSnapshot(items: items)
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, snapshot: PasteboardSnapshot) {
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

    private func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9  // "v"
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
