import AppKit
import SwiftUI

/// A floating, non-activating pill at the bottom-center of the main screen
/// that surfaces live recording feedback — animated audio-level bars plus
/// an elapsed-time readout while recording, and a spinner + status label
/// while the pipeline transcribes / polishes / injects afterwards.
///
/// Modeled after the HUDs in Typeless, Wispr Flow, etc. — the user's hotkey
/// fires in whatever app they're currently in, so this HUD must:
///   - never steal keyboard focus (`.nonactivatingPanel`, `isFloatingPanel`)
///   - float above regular windows (`.statusBar` level)
///   - ride along across Spaces / full-screen apps
///   - swallow no mouse events (`ignoresMouseEvents = true`) — purely status
@MainActor
final class RecordingHUDController {

    private let stateMachine: StateMachine
    private let meter: AudioLevelMeter
    private var panel: NSPanel?

    init(stateMachine: StateMachine, meter: AudioLevelMeter) {
        self.stateMachine = stateMachine
        self.meter = meter
        startObserving()
        applyState()
    }

    private func startObserving() {
        withObservationTracking {
            _ = stateMachine.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyState()
                self.startObserving()
            }
        }
    }

    private func applyState() {
        switch stateMachine.state {
        case .idle, .error:
            hide()
        case .recording, .transcribing, .polishing, .injecting:
            show()
        }
    }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        updatePanelLayout(p)
        p.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let view = RecordingHUDView(stateMachine: stateMachine, meter: meter)
        let host = NSHostingController(rootView: view)
        // Size the hosting view to hug the pill; the panel content area
        // will mirror that. The actual pill shape is drawn inside the view
        // on a clear panel background.
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = host
        p.isFloatingPanel = true
        // .statusBar sits above normal windows but below dock/menu bar —
        // right spot for a transient HUD.
        p.level = .statusBar
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        p.ignoresMouseEvents = true
        return p
    }

    private func updatePanelLayout(_ panel: NSPanel) {
        let targetSize = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let frame = RecordingHUDLayout.frame(
            panelSize: targetSize,
            visibleFrame: preferredVisibleFrame()
        )
        panel.setFrame(frame, display: true)
    }

    private func preferredVisibleFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }
}

struct RecordingHUDLayout {

    static let minWidth: CGFloat = 220
    static let minHeight: CGFloat = 46
    static let sideMargin: CGFloat = 16
    static let bottomMargin: CGFloat = 28

    static func frame(panelSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let availableWidth = max(minWidth, visibleFrame.width - sideMargin * 2)
        let width = min(max(minWidth, ceil(panelSize.width)), availableWidth)
        let height = max(minHeight, ceil(panelSize.height))

        let centeredX = visibleFrame.midX - width / 2
        let minX = visibleFrame.minX + sideMargin
        let maxX = visibleFrame.maxX - sideMargin - width
        let x = min(max(centeredX, minX), maxX)

        let y = visibleFrame.minY + bottomMargin
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - SwiftUI

struct RecordingHUDView: View {

    let stateMachine: StateMachine
    let meter: AudioLevelMeter

    var body: some View {
        Group {
            switch stateMachine.state {
            case .recording:
                recordingBody
            case .transcribing, .polishing, .injecting:
                pipelineBody
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: RecordingHUDLayout.minWidth)
        .background(background)
        .padding(4)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var recordingBody: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            WaveformBarsView(meter: meter)
                .frame(width: 180, height: 18)

            ElapsedTimeView(meter: meter)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private var pipelineBody: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
        }
    }

    private var background: some View {
        Capsule(style: .continuous)
            .fill(.black.opacity(0.84))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    private var icon: String {
        switch stateMachine.state {
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .polishing:    return "sparkles"
        case .injecting:    return "keyboard"
        default:            return "mic"
        }
    }

    private var tint: Color {
        switch stateMachine.state {
        case .recording: return .red
        default:         return .white.opacity(0.9)
        }
    }

    private var label: String {
        switch stateMachine.state {
        case .recording:    return String(localized: "Recording")
        case .transcribing: return String(localized: "Transcribing…")
        case .polishing:    return String(localized: "Polishing…")
        case .injecting:    return String(localized: "Inserting…")
        default:            return ""
        }
    }
}

/// Renders a row of vertical capsule bars whose heights animate to match
/// the most recent audio-level history pulled from `meter`. Drives itself
/// off `TimelineView(.animation)` so it redraws every frame without any
/// Combine/observation plumbing — the meter's read side is cheap (one
/// lock, one array copy ~64 floats).
private struct WaveformBarsView: View {

    let meter: AudioLevelMeter
    let barCount: Int = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let levels = meter.history(count: barCount)
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { i in
                        Capsule()
                            .fill(barColor(level: levels[i]))
                            .frame(
                                width: max(2, (geo.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)),
                                height: barHeight(level: levels[i], maxHeight: geo.size.height)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func barHeight(level: Float, maxHeight: CGFloat) -> CGFloat {
        // Keep the waveform visually active but compact, closer to Typeless'
        // flatter recording strip than a tall equalizer.
        let minH: CGFloat = 4
        let l = CGFloat(max(0, min(1, level)))
        return minH + (maxHeight - minH) * l
    }

    private func barColor(level: Float) -> Color {
        let l = Double(max(0, min(1, level)))
        return Color(
            .sRGB,
            red: 1.0,
            green: 1.0,
            blue: 1.0,
            opacity: 0.45 + 0.55 * l
        )
    }
}

/// Monospaced `m:ss` counter driven off `meter.startedAt`. Ticks every
/// 100ms via `TimelineView(.periodic)` so seconds roll over smoothly.
private struct ElapsedTimeView: View {
    let meter: AudioLevelMeter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = meter.startedAt.map { context.date.timeIntervalSince($0) } ?? 0
            Text(format(elapsed))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
