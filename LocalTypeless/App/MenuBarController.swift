import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let stateMachine: StateMachine
    private let modelStatusStore: ModelStatusStore
    private let settings: AppSettings
    private let modelSlots: [EngineModelSlot]
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void
    private let onUnloadModels: () -> Void

    init(
        stateMachine: StateMachine,
        modelStatusStore: ModelStatusStore,
        settings: AppSettings,
        modelSlots: [EngineModelSlot],
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onUnloadModels: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.stateMachine = stateMachine
        self.modelStatusStore = modelStatusStore
        self.settings = settings
        self.modelSlots = modelSlots
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onUnloadModels = onUnloadModels
        refresh()
        startObserving()
    }

    private func refresh() {
        configureMenu()
        refreshIcon()
    }

    private func configureMenu() {
        let menu = NSMenu()

        for slot in modelSlots {
            let item = NSMenuItem(
                title: menuTitle(for: slot, status: modelStatusStore.status(for: slot.kind)),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
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
            for slot in modelSlots {
                _ = modelStatusStore.status(for: slot.kind)
            }
            _ = settings.polishMode
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

    private func menuTitle(for slot: EngineModelSlot, status: ModelStatus) -> String {
        switch slot.role {
        case .speech:
            return String(
                format: String(localized: "ASR model: %@"),
                status.displayLabel
            )
        case .polish:
            return String(
                format: String(localized: "Polish model: %@"),
                polishDisplayLabel(for: status)
            )
        }
    }

    private func polishDisplayLabel(for status: ModelStatus) -> String {
        switch settings.polishMode {
        case .off:
            return String(localized: "off")
        case .automatic:
            return automaticPolishDisplayLabel(for: status)
        case .on:
            return explicitPolishDisplayLabel(for: status)
        }
    }

    private func automaticPolishDisplayLabel(for status: ModelStatus) -> String {
        switch status {
        case .notDownloaded:
            return String(localized: "not downloaded (optional)")
        case .downloading, .loading, .failed:
            return status.displayLabel
        case .downloaded, .resident:
            let snapshot = MemoryAdvisor.currentSnapshot()
            guard MemoryAdvisor.shouldUsePolishAutomatically(snapshot: snapshot) else {
                return String(localized: "auto skipped (low memory)")
            }
            return status == .resident
                ? String(localized: "ready (in memory)")
                : String(localized: "ready on demand")
        }
    }

    private func explicitPolishDisplayLabel(for status: ModelStatus) -> String {
        switch status {
        case .downloaded, .resident:
            let snapshot = MemoryAdvisor.currentSnapshot()
            guard MemoryAdvisor.canUsePolishWhenExplicitlyEnabled(snapshot: snapshot) else {
                return String(localized: "skipped (low memory)")
            }
            return status == .resident
                ? String(localized: "ready (in memory)")
                : String(localized: "ready on demand")
        case .notDownloaded, .downloading, .loading, .failed:
            return status.displayLabel
        }
    }
}

// MARK: - ModelStatus display helpers

private extension ModelStatus {
    var displayLabel: String {
        switch self {
        case .notDownloaded:          return String(localized: "not downloaded")
        case .downloading(let p):     return String(localized: "downloading (\(Int(p * 100))%)")
        case .downloaded:             return String(localized: "ready on demand")
        case .loading:                return String(localized: "loading…")
        case .resident:               return String(localized: "ready (in memory)")
        case .failed(let message):    return String(localized: "failed: \(message)")
        }
    }
}
