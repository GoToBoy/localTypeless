import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var hotkeyManager: HotkeyManager!
    private var recorder: Recorder!
    private var audioBuffer: AudioBuffer!
    private var stateMachine: StateMachine!
    private var asrService: ASRService!
    private var polishService: PolishService!
    private var textInjector: TextInjector!
    private var historyStore: HistoryStore?
    private var audioStore: AudioStore?
    private var menuBarController: MenuBarController!
    private var pipeline: DictationPipeline!
    private var mediaController: MediaController!

    private var modelManager: (any ASRModelManaging)!
    private var mlxPolishManager: (any PolishModelManaging)!
    private var modelStatusStore: ModelStatusStore!
    private var modelDownloadWindow: NSWindow?

    private var permissionChecker: PermissionChecker!
    private var firstRunState: FirstRunState!
    private var onboardingWindow: NSWindow?

    private var settings: AppSettings!
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var recordingStart: Date?
    private var focusedBundleId: String?
    private var focusedAppName: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        audioBuffer = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        recorder = Recorder(buffer: audioBuffer)
        stateMachine = StateMachine()
        modelStatusStore = ModelStatusStore()
        modelManager = WhisperKitModelManager(store: modelStatusStore)
        mlxPolishManager = MLXPolishModelManager(store: modelStatusStore)
        asrService = WhisperKitASRService(manager: modelManager)
        polishService = MLXPolishService(manager: mlxPolishManager)
        textInjector = TextInjector()
        mediaController = MediaController()
        historyStore = Self.makeHistoryStore()
        if historyStore == nil {
            let alert = NSAlert()
            alert.messageText = "Could not open history database"
            alert.informativeText = "Dictation will still work, but transcripts won't be saved to history."
            alert.alertStyle = .warning
            alert.runModal()
        }

        menuBarController = MenuBarController(
            stateMachine: stateMachine,
            modelStatusStore: modelStatusStore,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenHistory: { [weak self] in self?.openHistory() },
            onUnloadModels: { [weak self] in self?.unloadModels() },
            onOpenModelDownload: { [weak self] kind in self?.openModelDownload(kind: kind) }
        )

        settings = AppSettings()
        AppSettings.applyUILanguagePreference(settings.uiLanguageMode)
        hotkeyManager = HotkeyManager()
        applyInjectorOptions()
        installHotkey()
        startObservingSettings()
        LaunchAtLogin.applySilently(settings.launchAtLogin)

        audioStore = try? AudioStore(directory: AudioStore.defaultDirectory())
        if settings.audioRetentionEnabled {
            try? audioStore?.pruneOlderThan(days: settings.audioRetentionDays)
        }

        pipeline = DictationPipeline(.init(
            asr: asrService,
            polish: polishService,
            injector: textInjector,
            historyStore: historyStore,
            audioStore: audioStore
        ))

        permissionChecker = PermissionChecker()
        firstRunState = FirstRunState()
        if !firstRunState.onboardingCompleted {
            openOnboarding()
        }

        Log.state.info("launched")
    }

    // MARK: - Settings observation

    private func startObservingSettings() {
        withObservationTracking {
            _ = settings.hotkeyBinding
            _ = settings.hotkeyMode
            _ = settings.asrLanguageMode
            _ = settings.launchAtLogin
            _ = settings.uiLanguageMode
            _ = settings.pasteMethod
            _ = settings.preserveClipboard
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                AppSettings.applyUILanguagePreference(self.settings.uiLanguageMode)
                self.applySettingsChange()
            }
        }
    }

    private func applySettingsChange() {
        installHotkey()
        if let whisperService = asrService as? WhisperKitASRService {
            whisperService.setOptions(ASROptions(forcedLanguage: {
                switch settings.asrLanguageMode {
                case .auto: return nil
                case .en: return "en"
                case .zh: return "zh"
                }
            }()))
        }
        applyInjectorOptions()
        LaunchAtLogin.applySilently(settings.launchAtLogin)
        startObservingSettings()  // re-register
    }

    private func installHotkey() {
        hotkeyManager.install(
            binding: settings.hotkeyBinding,
            mode: settings.hotkeyMode,
            onPress: { [weak self] in self?.handleHotkeyPress() },
            onRelease: { [weak self] in self?.handleHotkeyRelease() }
        )
    }

    private func applyInjectorOptions() {
        textInjector.options = TextInjector.Options(
            pasteMethod: settings.pasteMethod,
            preserveClipboard: settings.preserveClipboard
        )
    }

    // MARK: - End-to-end loop

    /// Guard that the ASR + polish models are loaded before we start anything.
    /// Returns `true` when both are ready; otherwise opens the relevant
    /// download window and returns `false`.
    private func ensureModelsReady() -> Bool {
        if !modelStatusStore.isReady(.asrWhisperLargeV3Turbo) {
            openModelDownload(kind: .asrWhisperLargeV3Turbo); return false
        }
        if !modelStatusStore.isReady(.polishQwen25_3bInstruct4bit) {
            openModelDownload(kind: .polishQwen25_3bInstruct4bit); return false
        }
        return true
    }

    private func handleHotkeyPress() {
        guard ensureModelsReady() else { return }

        switch (settings.hotkeyMode.effective(for: settings.hotkeyBinding), stateMachine.state) {
        case (.toggle, .idle), (.pushToTalk, .idle):
            startRecording()
        case (.toggle, .recording):
            stopRecordingAndRunPipeline()
        case (.toggle, .error), (.pushToTalk, .error):
            stateMachine.toggle()  // -> idle
        default:
            break
        }
    }

    private func handleHotkeyRelease() {
        guard settings.hotkeyMode.effective(for: settings.hotkeyBinding) == .pushToTalk else { return }
        guard stateMachine.state == .recording else { return }
        stopRecordingAndRunPipeline()
    }

    private func startRecording() {
        captureFocusedApp()
        do {
            try recorder.start()
            recordingStart = Date()
            stateMachine.toggle()  // idle -> recording
            if settings.pauseMediaDuringRecording {
                Task { [mediaController] in await mediaController?.pauseIfPlaying() }
            }
        } catch {
            Log.recorder.error("start failed: \(String(describing: error), privacy: .public)")
            stateMachine.fail(message: "Recording failed")
        }
    }

    private func stopRecordingAndRunPipeline() {
        recorder.stop()
        stateMachine.toggle()  // recording -> transcribing
        if settings.pauseMediaDuringRecording {
            mediaController.resumeIfPaused()
        }
        Task { await runPipeline() }
    }

    private func runPipeline() async {
        let startedAt = recordingStart ?? Date()
        let input = DictationPipeline.Input(
            audioBuffer: audioBuffer,
            startedAt: startedAt,
            targetAppBundleId: focusedBundleId,
            targetAppName: focusedAppName,
            polishPrompt: settings.polishPromptOverride,
            transcribeTimeout: 60,
            polishTimeout: 30,
            saveAudio: settings.audioRetentionEnabled,
            audioRetentionDays: settings.audioRetentionDays
        )
        await pipeline.run(input) { [weak self] event in
            self?.handlePipelineEvent(event)
        }
    }

    private func handlePipelineEvent(_ event: DictationPipeline.Event) {
        switch event {
        case .transcribing:
            // StateMachine already moved to `.transcribing` when the hotkey
            // stopped recording; nothing to do.
            break
        case .polishing:
            stateMachine.advance()   // transcribing -> polishing
        case .injecting:
            stateMachine.advance()   // polishing -> injecting
        case .done:
            stateMachine.advance()   // injecting -> idle
        case .failed(let message):
            stateMachine.fail(message: message)
        }
    }

    private func captureFocusedApp() {
        let app = NSWorkspace.shared.frontmostApplication
        focusedBundleId = app?.bundleIdentifier
        focusedAppName = app?.localizedName
    }

    private func unloadModels() {
        Log.menu.info("unload models requested")
        Task { [modelManager, mlxPolishManager] in
            await modelManager!.unload(.asrWhisperLargeV3Turbo)
            await mlxPolishManager!.unload(.polishQwen25_3bInstruct4bit)
        }
    }

    // MARK: - Model download window

    private func openModelDownload(kind: ModelKind) {
        let manager: any ModelLifecycle
        switch kind {
        case .asrWhisperLargeV3Turbo:       manager = modelManager
        case .polishQwen25_3bInstruct4bit:   manager = mlxPolishManager
        }
        let view = ModelDownloadView(
            store: modelStatusStore,
            kind: kind,
            onStart: { [weak self] in self?.startModelDownload(kind: kind, manager: manager) },
            onCancel: { [weak self] in self?.modelDownloadWindow?.close() }
        )
        let host = NSHostingController(rootView: view)
        if let w = modelDownloadWindow {
            w.contentViewController = host
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let w = NSWindow(contentViewController: host)
        w.title = "Model Setup"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        modelDownloadWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func startModelDownload(kind: ModelKind, manager: any ModelLifecycle) {
        Task {
            do {
                try await manager.ensureReady(kind)
            } catch {
                Log.state.error("model download failed (\(kind.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Window management

    private func openOnboarding() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = OnboardingView(checker: permissionChecker) { [weak self] in
            self?.firstRunState.markOnboardingCompleted()
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = String(localized: "Welcome")
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        onboardingWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let view = SettingsView(
            settings: settings,
            modelStatusStore: modelStatusStore,
            onDownloadAsr: { [weak self] in self?.openModelDownload(kind: .asrWhisperLargeV3Turbo) },
            onDownloadPolish: { [weak self] in self?.openModelDownload(kind: .polishQwen25_3bInstruct4bit) },
            firstRunState: firstRunState,
            onReopenOnboarding: { [weak self] in self?.openOnboarding() }
        )
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Settings"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func openHistory() {
        if let w = historyWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        guard let historyStore else { return }
        let host = NSHostingController(rootView: HistoryView(store: historyStore))
        let w = NSWindow(contentViewController: host)
        w.title = "History"
        w.styleMask = [.titled, .closable, .resizable]
        w.center()
        w.isReleasedWhenClosed = false
        historyWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Persistence helpers

    private static func makeHistoryStore() -> HistoryStore? {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask)[0]
            .appendingPathComponent("local-typeless", isDirectory: true)
        let dbURL = supportDir.appendingPathComponent("history.sqlite")
        do {
            return try SQLiteHistoryStore(path: dbURL)
        } catch {
            Log.state.error("history store open failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
