import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var hotkeyManager: HotkeyManager!
    private var recorder: Recorder!
    private var audioBuffer: AudioBuffer!
    private var audioLevelMeter: AudioLevelMeter!
    private var stateMachine: StateMachine!
    private var engine: (any DictationEngine)!
    private var textInjector: TextInjector!
    private var historyStore: HistoryStore?
    private var audioStore: AudioStore?
    private var menuBarController: MenuBarController!
    private var recordingHUD: RecordingHUDController!
    private var pipeline: DictationPipeline!
    private var mediaController: MediaController!

    private var modelStatusStore: ModelStatusStore!
    private var modelDownloadWindow: NSWindow?
    private var asrPrewarmTask: Task<Void, Never>?

    private var permissionChecker: PermissionChecker!
    private var firstRunState: FirstRunState!
    private var onboardingWindow: NSWindow?

    private var settings: AppSettings!
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var recordingStart: Date?
    private var focusedProcessIdentifier: pid_t?
    private var focusedBundleId: String?
    private var focusedAppName: String?
    private var lastUserProcessIdentifier: pid_t?
    private var lastUserBundleId: String?
    private var lastUserAppName: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        audioBuffer = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        audioLevelMeter = AudioLevelMeter()
        recorder = Recorder(buffer: audioBuffer, meter: audioLevelMeter)
        stateMachine = StateMachine()
        modelStatusStore = ModelStatusStore()
        modelStatusStore.refreshDownloadedStatuses()
        engine = EngineFactory.make(store: modelStatusStore)
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

        settings = AppSettings()
        AppSettings.applyUILanguagePreference(settings.uiLanguageMode)

        menuBarController = MenuBarController(
            stateMachine: stateMachine,
            modelStatusStore: modelStatusStore,
            settings: settings,
            modelSlots: engine.modelSlots,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenHistory: { [weak self] in self?.openHistory() },
            onUnloadModels: { [weak self] in self?.unloadModels() }
        )
        recordingHUD = RecordingHUDController(
            stateMachine: stateMachine,
            meter: audioLevelMeter,
            onCancelRecording: { [weak self] in self?.cancelRecordingFromHUD() },
            onFinishRecording: { [weak self] in self?.finishRecordingFromHUD() }
        )

        hotkeyManager = HotkeyManager()
        applyInjectorOptions()
        installHotkey()
        startObservingSettings()
        startObservingFrontmostApplication()
        LaunchAtLogin.applySilently(settings.launchAtLogin)

        audioStore = try? AudioStore(directory: AudioStore.defaultDirectory())
        if settings.audioRetentionEnabled {
            try? audioStore?.pruneOlderThan(days: settings.audioRetentionDays)
        }

        pipeline = DictationPipeline(.init(
            asr: engine.asr,
            polish: engine.polish,
            injector: textInjector,
            historyStore: historyStore,
            audioStore: audioStore
        ))

        permissionChecker = PermissionChecker()
        firstRunState = FirstRunState()
        if !firstRunState.onboardingCompleted {
            openOnboarding()
        }

        scheduleASRPrewarmIfPossible()
        applyPolishMemoryPolicy()

        Log.state.info("launched")
    }

    // MARK: - Settings observation

    private func startObservingSettings() {
        withObservationTracking {
            _ = settings.hotkeyBinding
            _ = settings.hotkeyMode
            _ = settings.asrLanguageMode
            _ = settings.polishMode
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
        engine.setASROptions(ASROptions(forcedLanguage: {
            switch settings.asrLanguageMode {
            case .auto: return nil
            case .en: return "en"
            case .zh: return "zh"
            }
        }()))
        applyInjectorOptions()
        LaunchAtLogin.applySilently(settings.launchAtLogin)
        applyPolishMemoryPolicy()
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

    /// Guard that required model files exist before recording starts. ASR is
    /// mandatory; the polish model is only required when the user explicitly
    /// enabled polish (`.on`). In `.automatic`, polish is best-effort and
    /// downloads happen on demand from Settings.
    private func ensureModelsDownloadedForRecording() -> Bool {
        modelStatusStore.refreshDownloadedStatuses()
        for kind in engine.requiredModelKinds {
            if kind == .polishQwen25_3bInstruct4bit && settings.polishMode != .on {
                continue
            }
            if !modelStatusStore.canLoadOnDemand(kind) {
                openModelDownload(kind: kind)
                return false
            }
        }
        return true
    }

    private func handleHotkeyPress() {
        guard ensureModelsDownloadedForRecording() else { return }

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
        if settings.pauseMediaDuringRecording {
            mediaController.resumeIfPaused()
        }
        guard audioLevelMeter.hasMeaningfulSpeech else {
            Log.recorder.info("recording discarded: no speech detected")
            stateMachine.cancelRecording()
            return
        }
        stateMachine.toggle()  // recording -> transcribing
        Task { await runPipeline() }
    }

    private func cancelRecordingFromHUD() {
        guard stateMachine.state == .recording else { return }
        recorder.stop()
        if settings.pauseMediaDuringRecording {
            mediaController.resumeIfPaused()
        }
        recordingStart = nil
        Log.recorder.info("recording canceled from HUD")
        stateMachine.cancelRecording()
    }

    private func finishRecordingFromHUD() {
        guard stateMachine.state == .recording else { return }
        stopRecordingAndRunPipeline()
    }

    private func runPipeline() async {
        let startedAt = recordingStart ?? Date()
        let polishDecision = await decidePolishForCurrentDictation()
        let input = DictationPipeline.Input(
            audioBuffer: audioBuffer,
            startedAt: startedAt,
            targetAppProcessIdentifier: focusedProcessIdentifier,
            targetAppBundleId: focusedBundleId,
            targetAppName: focusedAppName,
            polishEnabled: polishDecision.enabled,
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
            stateMachine.startInjecting()
        case .copyFallback(let text, let reason):
            Task { @MainActor [weak self] in
                self?.showCopyFallbackPrompt(text: text, reason: reason)
            }
        case .done:
            stateMachine.finish()
        case .failed(let message):
            stateMachine.fail(message: message)
        }
    }

    private func captureFocusedApp() {
        let app = pasteTargetCandidate(NSWorkspace.shared.frontmostApplication)
        if let app {
            rememberUserApplication(app)
        }
        if app == nil, let lastUserProcessIdentifier {
            focusedProcessIdentifier = lastUserProcessIdentifier
            focusedBundleId = lastUserBundleId
            focusedAppName = lastUserAppName
            return
        }
        focusedProcessIdentifier = app?.processIdentifier
        focusedBundleId = app?.bundleIdentifier
        focusedAppName = app?.localizedName
    }

    private func startObservingFrontmostApplication() {
        rememberUserApplicationIfNeeded(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostApplicationDidChange(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        rememberUserApplicationIfNeeded(app)
    }

    private func rememberUserApplicationIfNeeded(_ app: NSRunningApplication?) {
        guard let app = pasteTargetCandidate(app) else { return }
        rememberUserApplication(app)
    }

    private func rememberUserApplication(_ app: NSRunningApplication) {
        lastUserProcessIdentifier = app.processIdentifier
        lastUserBundleId = app.bundleIdentifier
        lastUserAppName = app.localizedName
    }

    private func pasteTargetCandidate(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, !app.isTerminated else { return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }
        guard app.activationPolicy == .regular else { return nil }
        return app
    }

    private func showCopyFallbackPrompt(text: String, reason: TextInjector.InjectionError) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Dictation text is ready")
        alert.informativeText = copyFallbackMessage(for: reason)
        let canOpenAccessibilitySettings = reason == .accessibilityDenied
        if canOpenAccessibilitySettings {
            alert.addButton(withTitle: String(localized: "Open Accessibility Settings"))
        }
        alert.addButton(withTitle: String(localized: "Copy"))
        alert.addButton(withTitle: String(localized: "Done"))
        NSApp.activate()

        let response = alert.runModal()
        if canOpenAccessibilitySettings, response == .alertFirstButtonReturn {
            PermissionChecker.openSystemSettings(for: .accessibility)
            return
        }

        let copyResponse: NSApplication.ModalResponse = canOpenAccessibilitySettings
            ? .alertSecondButtonReturn
            : .alertFirstButtonReturn
        if response == copyResponse {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    private func copyFallbackMessage(for reason: TextInjector.InjectionError) -> String {
        switch reason {
        case .accessibilityDenied:
            return String(localized: "local-typeless could not paste automatically because Accessibility permission is not enabled. The text is on the clipboard.")
        case .noFocusedWindow:
            return String(localized: "No focused window was available. The text is on the clipboard, ready to paste wherever you want.")
        case .eventCreationFailed, .appleScriptFailed(_), .pasteFailed(_):
            return String(localized: "local-typeless could not paste automatically. The text is on the clipboard, ready to paste wherever you want.")
        }
    }

    private struct PolishDecision {
        let enabled: Bool
    }

    private func decidePolishForCurrentDictation() async -> PolishDecision {
        let kind = ModelKind.polishQwen25_3bInstruct4bit
        switch settings.polishMode {
        case .off:
            await unloadPolishIfResident()
            return .init(enabled: false)
        case .automatic:
            guard modelStatusStore.canLoadOnDemand(kind) else {
                return .init(enabled: false)
            }
            let snapshot = MemoryAdvisor.currentSnapshot()
            guard MemoryAdvisor.shouldUsePolishAutomatically(snapshot: snapshot) else {
                await unloadPolishIfResident()
                Log.polish.info("polish skipped automatically; available memory \(snapshot.availableDescription, privacy: .public)")
                return .init(enabled: false)
            }
            return .init(enabled: true)
        case .on:
            guard modelStatusStore.canLoadOnDemand(kind) else {
                return .init(enabled: false)
            }
            let snapshot = MemoryAdvisor.currentSnapshot()
            guard MemoryAdvisor.canUsePolishWhenExplicitlyEnabled(snapshot: snapshot) else {
                await unloadPolishIfResident()
                Log.polish.info("polish skipped; available memory \(snapshot.availableDescription, privacy: .public)")
                return .init(enabled: false)
            }
            return .init(enabled: true)
        }
    }

    private func applyPolishMemoryPolicy() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = MemoryAdvisor.currentSnapshot()
            switch self.settings.polishMode {
            case .off:
                await self.unloadPolishIfResident()
            case .automatic:
                if !MemoryAdvisor.shouldUsePolishAutomatically(snapshot: snapshot) {
                    await self.unloadPolishIfResident()
                }
            case .on:
                if !MemoryAdvisor.canUsePolishWhenExplicitlyEnabled(snapshot: snapshot) {
                    await self.unloadPolishIfResident()
                }
            }
        }
    }

    private func unloadPolishIfResident() async {
        guard modelStatusStore.isReady(.polishQwen25_3bInstruct4bit) else { return }
        await engine.unload(.polishQwen25_3bInstruct4bit)
    }

    private func scheduleASRPrewarmIfPossible() {
        asrPrewarmTask?.cancel()
        asrPrewarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.prewarmASRIfPossible()
        }
    }

    private func prewarmASRIfPossible() async {
        modelStatusStore.refreshDownloadedStatuses()
        guard let kind = engine.speechModelKind,
              modelStatusStore.canLoadOnDemand(kind),
              !modelStatusStore.isReady(kind) else {
            return
        }
        let snapshot = MemoryAdvisor.currentSnapshot()
        guard MemoryAdvisor.canPrewarmASR(snapshot: snapshot) else {
            Log.asr.info("ASR prewarm skipped; available memory \(snapshot.availableDescription, privacy: .public)")
            return
        }
        do {
            try await engine.download(kind)
        } catch {
            Log.asr.error("ASR prewarm failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func unloadModels() {
        Log.menu.info("unload models requested")
        Task { [engine] in
            await engine?.unloadAllModels()
        }
    }

    // MARK: - Model download window

    private func openModelDownload(kind: ModelKind) {
        let view = ModelDownloadView(
            store: modelStatusStore,
            kind: kind,
            onStart: { [weak self] in self?.startModelDownload(kind: kind) },
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

    private func startModelDownload(kind: ModelKind) {
        Task { [engine] in
            do {
                try await engine?.download(kind)
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
            requiredModelKinds: engine.requiredModelKinds,
            polishAvailable: engine.polish != nil,
            onDownload: { [weak self] kind in self?.openModelDownload(kind: kind) },
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
