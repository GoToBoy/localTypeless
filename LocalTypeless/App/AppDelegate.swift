import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var hotkeyManager: HotkeyManager!
    private var recorder: Recorder!
    private var audioBuffer: AudioBuffer!
    private var audioLevelMeter: AudioLevelMeter!
    private var recordingHUD: RecordingHUDController!
    private var stateMachine: StateMachine!
    private var asrService: ASRService!
    private var polishService: PolishService!
    private var textInjector: TextInjector!
    private var historyStore: HistoryStore?
    private var audioStore: AudioStore?
    private var menuBarController: MenuBarController!

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
    private var didWarnAboutMissingRecordingHardware = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ModelStorage.migrateLegacyCachesIfNeeded()

        audioBuffer = AudioBuffer(maxSeconds: 120, sampleRate: 16_000)
        audioLevelMeter = AudioLevelMeter()
        recorder = Recorder(buffer: audioBuffer, meter: audioLevelMeter)
        stateMachine = StateMachine()
        recordingHUD = RecordingHUDController(
            stateMachine: stateMachine,
            meter: audioLevelMeter
        )
        modelStatusStore = ModelStatusStore()
        modelManager = WhisperKitModelManager(store: modelStatusStore)
        mlxPolishManager = MLXPolishModelManager(store: modelStatusStore)

        // Recognize models the user already has on disk from a prior launch,
        // and warm them into RAM in the background so the first hotkey press
        // doesn't surface the download window.
        probeAndPreloadExistingModels()
        asrService = WhisperKitASRService(manager: modelManager)
        polishService = MLXPolishService(manager: mlxPolishManager)
        textInjector = TextInjector()
        historyStore = Self.makeHistoryStore()
        if historyStore == nil {
            let alert = NSAlert()
            // BUG-L04 fix: wrap in String(localized:) so zh-Hans translations apply.
            alert.messageText = String(localized: "Could not open history database")
            alert.informativeText = String(localized: "Dictation will still work, but transcripts won't be saved to history.")
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
        let binding = settings.hotkeyBinding
        hotkeyManager.install(binding: binding) { [weak self] in self?.handleToggle() }
        startObservingSettings()
        LaunchAtLogin.applySilently(settings.launchAtLogin)

        audioStore = try? AudioStore(directory: AudioStore.defaultDirectory())
        if settings.audioRetentionEnabled {
            try? audioStore?.pruneOlderThan(days: settings.audioRetentionDays)
        }

        permissionChecker = PermissionChecker()
        validateRecordingHardwareAtLaunch()
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
            _ = settings.asrLanguageMode
            _ = settings.launchAtLogin
            _ = settings.uiLanguageMode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                AppSettings.applyUILanguagePreference(self.settings.uiLanguageMode)
                self.applySettingsChange()
            }
        }
    }

    private func applySettingsChange() {
        hotkeyManager.install(binding: settings.hotkeyBinding) { [weak self] in
            self?.handleToggle()
        }
        if let whisperService = asrService as? WhisperKitASRService {
            whisperService.setOptions(ASROptions(forcedLanguage: {
                switch settings.asrLanguageMode {
                case .auto: return nil
                case .en: return "en"
                case .zh: return "zh"
                }
            }()))
        }
        LaunchAtLogin.applySilently(settings.launchAtLogin)
        startObservingSettings()  // re-register
    }

    // MARK: - End-to-end loop

    private func handleToggle() {
        // Gate on model readiness before starting any dictation.
        //
        // Three buckets, distinct UX:
        //   - .resident: proceed.
        //   - .notDownloaded / .failed: genuinely missing — open the
        //     download window so the user can fetch it.
        //   - .downloaded / .loading / .downloading: the bits are either on
        //     disk or on the way; opening the download window here is
        //     confusing ("why is it asking me to download something I
        //     already have?"). Kick the load task (idempotent on the
        //     manager actor) and tell the user to wait instead.
        for kind in [ModelKind.asrWhisperLargeV3Turbo, .polishQwen25_3bInstruct4bit] {
            switch modelStatusStore.status(for: kind) {
            case .resident:
                continue
            case .notDownloaded, .failed:
                openModelDownload(kind: kind)
                return
            case .downloaded, .loading, .downloading:
                ensureModelLoadInFlight(kind: kind)
                notifyModelStillLoading(kind: kind)
                return
            }
        }

        switch stateMachine.state {
        case .idle:
            guard ensureRecordingHardwareAvailable() else { return }
            captureFocusedApp()
            do {
                try recorder.start()
                recordingStart = Date()
                stateMachine.toggle()
            } catch Recorder.RecorderError.inputDeviceNotReady {
                // The HAL was momentarily unable to resolve the default
                // input device (common right at launch before AudioEngine
                // warms up). Recorder already unwound its tap, so we can
                // stay in `.idle` and let the user press again instead of
                // parking in the `.error` state, which would force them
                // to press twice more (once to clear .error, once to
                // retry). Soft alert — not a fatal banner.
                Log.recorder.error("input device not ready at hotkey press")
                notifyMicrophoneNotReady()
            } catch Recorder.RecorderError.installTapFailed {
                // AVAudioEngine raised an NSException from installTap
                // (caught by SafeAudioTap). We're alive, the tap is
                // unwound, but we don't actually know which underlying
                // cause hit us — surface a generic retry prompt.
                Log.recorder.error("installTap threw NSException at hotkey press")
                notifyMicrophoneNotReady()
            } catch {
                Log.recorder.error("start failed: \(String(describing: error), privacy: .public)")
                stateMachine.fail(message: "Recording failed")
            }

        case .recording:
            recorder.stop()
            stateMachine.toggle()  // recording -> transcribing
            Task { await runPipeline() }

        case .error:
            // BUG-U01 fix: previously the error branch only cleared to .idle,
            // requiring a second hotkey press to start recording.  Users had no
            // visual feedback that the first press was received (HUD is hidden
            // in both .error and .idle states), so the app appeared unresponsive.
            // We now clear the error and immediately attempt to start recording
            // in one press, matching user expectation ("press = start talking").
            stateMachine.toggle()  // error -> idle
            guard ensureRecordingHardwareAvailable() else { return }
            captureFocusedApp()
            do {
                try recorder.start()
                recordingStart = Date()
                stateMachine.toggle()  // idle -> recording
            } catch Recorder.RecorderError.inputDeviceNotReady {
                Log.recorder.error("input device not ready (error recovery path)")
                notifyMicrophoneNotReady()
            } catch Recorder.RecorderError.installTapFailed {
                Log.recorder.error("installTap failed (error recovery path)")
                notifyMicrophoneNotReady()
            } catch {
                Log.recorder.error("start failed (error recovery): \(String(describing: error), privacy: .public)")
                stateMachine.fail(message: "Recording failed")
            }

        default:
            break
        }
    }

    private func runPipeline() async {
        let startedAt = recordingStart ?? Date()
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)

        let transcript: Transcript
        do {
            transcript = try await withTimeout(60) { [asrService, audioBuffer] in
                try await asrService.transcribe(audioBuffer)
            }
        } catch PipelineTimeoutError.timedOut {
            stateMachine.fail(message: "Transcription timed out")
            return
        } catch {
            stateMachine.fail(message: "ASR failed")
            return
        }

        if settings.audioRetentionEnabled, let store = audioStore {
            do {
                let samples = audioBuffer.snapshot()
                try store.save(samples: samples, sampleRate: 16_000)
                try store.pruneOlderThan(days: settings.audioRetentionDays)
            } catch {
                Log.state.error("audio save failed: \(String(describing: error), privacy: .public)")
            }
        }

        stateMachine.advance()  // transcribing -> polishing

        let promptOverride = settings.polishPromptOverride
        let polished: String
        do {
            polished = try await withTimeout(30) { [polishService] in
                try await polishService.polish(transcript, prompt: promptOverride)
            }
        } catch {
            Log.polish.error("polish failed — using raw transcript")
            polished = transcript.text
        }

        stateMachine.advance()  // polishing -> injecting

        // BUG-F03 defence: if both ASR and the polish fallback produced empty
        // text, skip injection entirely.  TextInjector also guards against this,
        // but an early exit here avoids an unnecessary state transition and
        // prevents the "paste nothing + clear clipboard" side-effect.
        if polished.isEmpty {
            Log.injector.info("empty result — skipping injection")
        } else {
            do {
                try await textInjector.inject(polished)
            } catch TextInjector.InjectionError.accessibilityDenied {
                Log.injector.warning("accessibility denied; polished text left on pasteboard")
            } catch {
                Log.injector.error("injection failed: \(String(describing: error), privacy: .public)")
            }
        }

        let entry = DictationEntry(
            startedAt: startedAt,
            durationMs: durationMs,
            rawTranscript: transcript.text,
            polishedText: polished,
            language: transcript.language,
            targetAppBundleId: focusedBundleId,
            targetAppName: focusedAppName
        )
        if let store = historyStore { try? store.insert(entry) }

        stateMachine.advance()  // injecting -> idle
    }

    private func captureFocusedApp() {
        let app = NSWorkspace.shared.frontmostApplication
        focusedBundleId = app?.bundleIdentifier
        focusedAppName = app?.localizedName
    }

    private func probeAndPreloadExistingModels() {
        for kind in ModelKind.allCases where ModelStorage.isDownloaded(kind) {
            modelStatusStore.set(.downloaded, for: kind)
        }
        for kind in ModelKind.allCases where modelStatusStore.status(for: kind) == .downloaded {
            ensureModelLoadInFlight(kind: kind)
        }
    }

    /// Kick the manager's `ensureReady` task for `kind` without blocking.
    ///
    /// Idempotent in practice: `ensureReady` is actor-isolated inside the
    /// manager, so calling it again while a prior load is in flight just
    /// queues a second call that returns immediately once the model is
    /// resident. Used both by the launch-time probe and by the hotkey gate
    /// when the user presses the shortcut while the warm-up is still in
    /// progress — we want to surface "loading" status, not offer download.
    private func ensureModelLoadInFlight(kind: ModelKind) {
        let manager: any ModelLifecycle
        switch kind {
        case .asrWhisperLargeV3Turbo:      manager = modelManager
        case .polishQwen25_3bInstruct4bit: manager = mlxPolishManager
        }
        Task {
            do {
                try await manager.ensureReady(kind)
            } catch {
                Log.state.error("background load failed (\(kind.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func validateRecordingHardwareAtLaunch() {
        guard !Recorder.hasUsableRecordingHardware() else { return }
        notifyMissingRecordingHardware()
    }

    private func ensureRecordingHardwareAvailable() -> Bool {
        guard !Recorder.hasUsableRecordingHardware() else { return true }
        notifyMissingRecordingHardware()
        return false
    }

    private func notifyMissingRecordingHardware() {
        let alert = NSAlert()
        alert.messageText = "No recording device detected"
        alert.informativeText = "local-typeless could not find a usable audio input device on this Mac. Connect a microphone, or choose an input device in System Settings > Sound > Input, before starting dictation."
        alert.addButton(withTitle: "OK")
        if didWarnAboutMissingRecordingHardware {
            Log.recorder.error("recording hardware missing")
            return
        }
        didWarnAboutMissingRecordingHardware = true
        alert.runModal()
        Log.recorder.error("recording hardware missing")
    }

    /// Soft alert for the "HAL hasn't resolved the default input yet" race.
    /// Distinct from permission denial — the mic permission is fine; the
    /// OS just isn't ready to hand us a device yet. Usually clears within
    /// a second or two.
    private func notifyMicrophoneNotReady() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Microphone not ready")
        alert.informativeText = String(
            localized: "macOS was still resolving the default input device. Try the hotkey again in a moment."
        )
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    /// Surface a brief "still loading" notice when the user triggers the
    /// hotkey while a model is mid-load. Avoids the jarring download-window
    /// pop-up for a model that's visibly on its way.
    private func notifyModelStillLoading(kind: ModelKind) {
        // Kind-specific messages — no string interpolation — so xcstrings can
        // translate the full sentence per locale without %@ substitution.
        let body: String
        switch kind {
        case .asrWhisperLargeV3Turbo:
            body = String(localized: "The speech model is still loading into memory. Please try the hotkey again in a few seconds.")
        case .polishQwen25_3bInstruct4bit:
            body = String(localized: "The polish model is still loading into memory. Please try the hotkey again in a few seconds.")
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Loading model…")
        alert.informativeText = body
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
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
        w.title = String(localized: "Model Setup") // BUG-L04 fix
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
                // BUG-U02 fix: once the model reaches .resident the download window
                // is no longer useful — auto-close it so the user isn't left with a
                // stale "Ready / Done" window blocking their workflow.
                await MainActor.run {
                    modelDownloadWindow?.close()
                }
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
        w.title = String(localized: "Settings") // BUG-L04 fix
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func openHistory() {
        guard let historyStore else { return }
        let freshView = HistoryView(store: historyStore, onReInject: { [weak self] text in
            Task { @MainActor in
                guard let self, !text.isEmpty else { return }
                try? await self.textInjector.inject(text)
            }
        })
        if let w = historyWindow {
            // BUG-F02 fix: replace the content view controller so SwiftUI
            // rebuilds the view from scratch and re-fires .task { reload() }.
            // Simply calling makeKeyAndOrderFront on the existing window would
            // reuse the old NSHostingController whose .task fires only once,
            // meaning new dictations are invisible until the app restarts.
            w.contentViewController = NSHostingController(rootView: freshView)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: freshView)
        let w = NSWindow(contentViewController: host)
        w.title = String(localized: "History")
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
