import AppKit
import Observation
import QuartzCore
import SwiftUI

/// A floating, non-activating pill that surfaces live recording feedback:
/// audio-level bars plus elapsed time while recording, then status text while
/// the pipeline transcribes, polishes, and injects.
@MainActor
final class RecordingHUDController {
    private let stateMachine: StateMachine
    private let meter: AudioLevelMeter
    private let onCancelRecording: @MainActor () -> Void
    private let onFinishRecording: @MainActor () -> Void
    private var panel: NSPanel?

    init(
        stateMachine: StateMachine,
        meter: AudioLevelMeter,
        onCancelRecording: @escaping @MainActor () -> Void,
        onFinishRecording: @escaping @MainActor () -> Void
    ) {
        self.stateMachine = stateMachine
        self.meter = meter
        self.onCancelRecording = onCancelRecording
        self.onFinishRecording = onFinishRecording
        refresh()
        startObserving()
    }

    private func startObserving() {
        withObservationTracking {
            _ = stateMachine.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.startObserving()
            }
        }
    }

    private func refresh() {
        switch stateMachine.state {
        case .idle, .error:
            hide()
        case .recording, .transcribing, .polishing, .injecting:
            show()
        }
    }

    private func show() {
        let panel = panel ?? makePanel()
        let wasVisible = panel.isVisible
        self.panel = panel
        panel.ignoresMouseEvents = stateMachine.state != .recording
        if let host = panel.contentViewController as? NSHostingController<RecordingHUDView> {
            host.rootView = RecordingHUDView(
                state: stateMachine.state,
                meter: meter,
                onCancelRecording: onCancelRecording,
                onFinishRecording: onFinishRecording
            )
        }
        position(panel)
        if wasVisible {
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(
            rootView: RecordingHUDView(
                state: stateMachine.state,
                meter: meter,
                onCancelRecording: onCancelRecording,
                onFinishRecording: onFinishRecording
            )
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = stateMachine.state != .recording
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        return panel
    }

    private func position(_ panel: NSPanel) {
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
    static let minWidth: CGFloat = 132
    static let minHeight: CGFloat = 28
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

struct RecordingHUDView: View {
    let state: DictationState
    let meter: AudioLevelMeter
    let onCancelRecording: @MainActor () -> Void
    let onFinishRecording: @MainActor () -> Void

    var body: some View {
        Group {
            switch state {
            case .recording:
                recordingBody
            case .transcribing, .polishing, .injecting:
                pipelineBody
            case .idle, .error:
                EmptyView()
            }
        }
        .background(background)
        .padding(2.4)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var recordingBody: some View {
        HStack(spacing: 7.2) {
            RecordingHUDControlButton(
                systemName: "xmark",
                foregroundColor: .white.opacity(0.92),
                backgroundColor: .white.opacity(0.18),
                hoverBackgroundColor: .white.opacity(0.28),
                action: onCancelRecording
            )

            WaveformBarsView(meter: meter)
                .frame(width: 54, height: 10.8)

            RecordingHUDControlButton(
                systemName: "checkmark",
                foregroundColor: .black.opacity(0.84),
                backgroundColor: .white,
                hoverBackgroundColor: Color(.sRGB, white: 0.92, opacity: 1),
                action: onFinishRecording
            )
        }
        .padding(3)
        .frame(width: 131, height: 36)
    }

    private var pipelineBody: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: RecordingHUDLayout.minWidth)
    }

    private var background: some View {
        Capsule(style: .continuous)
            .fill(.black.opacity(0.92))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.6)
            )
    }

    private var icon: String {
        switch state {
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .polishing: return "sparkles"
        case .injecting: return "keyboard"
        case .idle, .error: return "mic"
        }
    }

    private var label: String {
        switch state {
        case .recording: return String(localized: "Recording")
        case .transcribing: return String(localized: "Transcribing…")
        case .polishing: return String(localized: "Polishing…")
        case .injecting: return String(localized: "Inserting…")
        case .idle, .error: return ""
        }
    }
}

private struct RecordingHUDControlButton: View {
    let systemName: String
    let foregroundColor: Color
    let backgroundColor: Color
    let hoverBackgroundColor: Color
    let action: @MainActor () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isHovering ? hoverBackgroundColor : backgroundColor)
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: 12.6, weight: .regular))
                        .foregroundStyle(foregroundColor)
                )
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isHovering ? 0.24 : 0), lineWidth: 0.6)
                )
                .frame(width: 27.6, height: 27.6)
                .scaleEffect(isHovering ? 1.04 : 1)
                .shadow(color: .black.opacity(isHovering ? 0.30 : 0), radius: 3, x: 0, y: 1.2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct WaveformBarsView: View {
    let meter: AudioLevelMeter
    private let markCount = 13
    private let markWidth: CGFloat = 1.8
    private let markSpacing: CGFloat = 2.52

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 50.0)) { timeline in
            let levels = meter.history(count: markCount)
            let liveLevel = meter.smoothedLevel
            let voiceActive = meter.isVoiceActive
            let time = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geometry in
                HStack(alignment: .center, spacing: markSpacing) {
                    ForEach(0..<markCount, id: \.self) { index in
                        let level = visualLevel(
                            levels: levels,
                            liveLevel: liveLevel,
                            index: index,
                            time: time,
                            voiceActive: voiceActive
                        )
                        Capsule()
                            .fill(barColor(level: level, voiceActive: voiceActive))
                            .frame(
                                width: markWidth,
                                height: barHeight(level: level, maxHeight: geometry.size.height)
                            )
                            .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.86), value: voiceActive)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func visualLevel(
        levels: [Float],
        liveLevel: Float,
        index: Int,
        time: TimeInterval,
        voiceActive: Bool
    ) -> CGFloat {
        let resting = quietLevel(at: index)
        guard voiceActive else { return resting }

        let current = clampedLevel(levels[index])
        let previous = index > 0 ? clampedLevel(levels[index - 1]) : current
        let next = index + 1 < levels.count ? clampedLevel(levels[index + 1]) : current
        let spatiallySmoothed = current * 0.62 + previous * 0.19 + next * 0.19

        let live = clampedLevel(liveLevel)
        let distanceFromCenter = abs(CGFloat(index) - CGFloat(markCount - 1) / 2)
        let normalizedDistance = distanceFromCenter / (CGFloat(markCount) / 2)
        let centerEnvelope = CGFloat(exp(-Double(normalizedDistance * normalizedDistance * 2.5)))
        let travelingWave = CGFloat((sin(time * 8.4 - Double(index) * 0.62) + 1) / 2)
        let counterWave = CGFloat((sin(time * 4.1 + Double(index) * 0.34) + 1) / 2)
        let flow = 0.68 * travelingWave + 0.32 * counterWave

        let liveLift = live * (0.14 + 0.18 * flow) * centerEnvelope
        let shapedSignal = spatiallySmoothed * (0.62 + 0.14 * flow)
        return min(1, max(resting, resting * 0.45 + shapedSignal + liveLift))
    }

    private func clampedLevel(_ level: Float) -> CGFloat {
        CGFloat(max(0, min(1, level)))
    }

    private func barHeight(level: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let minimumHeight: CGFloat = 1.8
        return minimumHeight + (maxHeight - minimumHeight) * level
    }

    private func barColor(level: CGFloat, voiceActive: Bool) -> Color {
        let level = Double(max(0, min(1, level)))
        let base = voiceActive ? 0.50 : 0.74
        let lift = voiceActive ? 0.48 : 0.18
        return Color(.sRGB, red: 1, green: 1, blue: 1, opacity: base + lift * level)
    }

    private func quietLevel(at index: Int) -> CGFloat {
        let position = CGFloat(index) / CGFloat(max(1, markCount - 1))
        let centered = abs(position - 0.5) * 2
        let envelope = CGFloat(exp(-Double(centered * centered * 2.8)))
        let texture = CGFloat((sin(Double(index) * 1.27) + 1) / 2)
        return envelope * 0.018 + texture * 0.010
    }
}

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
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
