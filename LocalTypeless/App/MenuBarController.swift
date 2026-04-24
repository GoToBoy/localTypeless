import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let stateMachine: StateMachine
    private let modelStatusStore: ModelStatusStore
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void
    private let onUnloadModels: () -> Void
    private let onOpenModelDownload: (ModelKind) -> Void

    init(
        stateMachine: StateMachine,
        modelStatusStore: ModelStatusStore,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onUnloadModels: @escaping () -> Void,
        onOpenModelDownload: @escaping (ModelKind) -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.stateMachine = stateMachine
        self.modelStatusStore = modelStatusStore
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onUnloadModels = onUnloadModels
        self.onOpenModelDownload = onOpenModelDownload
        refresh()
        startObserving()
    }

    private func refresh() {
        configureMenu()
        refreshIcon()
    }

    private func configureMenu() {
        let menu = NSMenu()

        // Per-model status + optional download action
        let modelEntries: [(ModelKind, String)] = [
            (.asrWhisperLargeV3Turbo,     String(localized: "ASR model")),
            (.polishQwen25_3bInstruct4bit, String(localized: "Polish model")),
        ]
        for (kind, name) in modelEntries {
            let status = modelStatusStore.status(for: kind)
            let statusLabel = NSMenuItem(
                title: String(localized: "\(name): \(status.displayLabel)"),
                action: nil, keyEquivalent: "")
            statusLabel.isEnabled = false
            menu.addItem(statusLabel)

            // Only surface the "Download…" item when the model is
            // genuinely missing. If the bits are on disk (`.downloaded`),
            // being fetched (`.downloading`), or already warming into RAM
            // (`.loading`), a download item is confusing — the same state
            // we already gate on in AppDelegate.handleToggle(). When the
            // status observer fires on the transition into `.resident`,
            // the menu rebuilds and the label flips to "ready".
            switch status {
            case .resident, .downloaded, .loading, .downloading:
                break
            case .notDownloaded, .failed:
                let dl = NSMenuItem(title: String(localized: "Download \(name)…"),
                                    action: #selector(downloadModelAction(_:)),
                                    keyEquivalent: "")
                dl.target = self
                dl.representedObject = kind.rawValue
                menu.addItem(dl)
            }
        }

        menu.addItem(.separator())

        let history = NSMenuItem(title: String(localized: "Open History"), action: #selector(openHistoryAction), keyEquivalent: "")
        history.target = self
        menu.addItem(history)
        let settings = NSMenuItem(title: String(localized: "Settings..."), action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let unload = NSMenuItem(title: String(localized: "Unload Models"), action: #selector(unloadAction), keyEquivalent: "")
        unload.target = self
        menu.addItem(unload)
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit local-typeless"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        self.statusItem.menu = menu
    }

    private func startObserving() {
        withObservationTracking {
            _ = stateMachine.state
            _ = modelStatusStore.status(for: .asrWhisperLargeV3Turbo)
            _ = modelStatusStore.status(for: .polishQwen25_3bInstruct4bit)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.startObserving()
            }
        }
    }

    private func refreshIcon() {
        let button = statusItem.button
        let (symbol, tooltip): (String, String) = {
            switch stateMachine.state {
            case .idle:         return ("mic", String(localized: "local-typeless — idle"))
            case .recording:    return ("record.circle.fill", String(localized: "Recording…"))
            case .transcribing: return ("waveform", String(localized: "Transcribing…"))
            case .polishing:    return ("sparkles", String(localized: "Polishing…"))
            case .injecting:    return ("keyboard", String(localized: "Inserting…"))
            case .error(let m): return ("exclamationmark.triangle", String(localized: "Error: \(m)"))
            }
        }()
        button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button?.toolTip = tooltip
    }

    @objc private func openSettingsAction() { onOpenSettings() }
    @objc private func openHistoryAction() { onOpenHistory() }
    @objc private func unloadAction() { onUnloadModels() }
    @objc private func downloadModelAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = ModelKind(rawValue: raw) else { return }
        onOpenModelDownload(kind)
    }
}

// MARK: - ModelStatus display helpers

private extension ModelStatus {
    var displayLabel: String {
        switch self {
        case .notDownloaded:          return String(localized: "not downloaded")
        case .downloading(let p):     return String(localized: "downloading (\(Int(p * 100))%)")
        case .downloaded:             return String(localized: "downloaded")
        case .loading:                return String(localized: "loading…")
        case .resident:               return String(localized: "ready")
        case .failed(let message):    return String(localized: "failed: \(message)")
        }
    }
}
