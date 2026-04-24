import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {

    typealias Handler = () -> Void

    private var onPress: Handler?
    private var onRelease: Handler?
    private var activeMode: HotkeyMode = .toggle
    private var modifierHeld = false

    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentBinding: HotkeyBinding?
    private var lastModifierPress: (key: HotkeyBinding.ModifierOnly, time: CFAbsoluteTime)?
    nonisolated(unsafe) private static var sharedInstance: HotkeyManager?

    init() {
        Self.sharedInstance = self
    }

    deinit {
        // deinit runs on the MainActor since the class is @MainActor-isolated;
        // use assumeIsolated to synchronously access actor-isolated state.
        MainActor.assumeIsolated {
            tearDown()
        }
    }

    /// Install a hotkey.
    ///
    /// - Parameters:
    ///   - binding: which key / modifier combination to listen for.
    ///   - mode: how a press maps to record start/stop. Falls back to `.toggle`
    ///     when the binding can't express a release (see `HotkeyMode`).
    ///   - onPress: fired on press (toggle) or press-down (push-to-talk).
    ///   - onRelease: fired on release in push-to-talk mode; never fired in
    ///     toggle mode.
    func install(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onPress: @escaping Handler,
        onRelease: @escaping Handler
    ) {
        tearDown()
        self.onPress = onPress
        self.onRelease = onRelease
        self.activeMode = mode.effective(for: binding)
        self.currentBinding = binding
        self.modifierHeld = false

        if binding.modifierOnly != nil {
            installEventTap(for: binding)
        } else if let keyCode = binding.keyCode {
            installCarbonHotkey(keyCode: keyCode, modifierMask: binding.modifierMask)
        } else {
            Log.hotkey.error("binding has neither keyCode nor modifierOnly")
        }
    }

    func tearDown() {
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
        if let h = carbonHandlerRef {
            RemoveEventHandler(h)
            carbonHandlerRef = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        currentBinding = nil
        modifierHeld = false
    }

    // MARK: - Carbon path (key + modifier)

    private func installCarbonHotkey(keyCode: UInt16, modifierMask: NSEvent.ModifierFlags) {
        let signature: FourCharCode = 0x4c544c53  // 'LTLS'
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, _) -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async {
                // Carbon hot-keys only report "pressed"; treat as a toggle press.
                HotkeyManager.sharedInstance?.onPress?()
            }
            return noErr
        } as EventHandlerUPP, 1, &eventType, nil, &carbonHandlerRef)

        let carbonMods = Self.carbonModifiers(from: modifierMask)
        RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                            GetApplicationEventTarget(), 0, &carbonHotKeyRef)
        Log.hotkey.info("carbon hotkey registered")
    }

    private static func carbonModifiers(from mask: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if mask.contains(.command) { m |= UInt32(cmdKey) }
        if mask.contains(.option)  { m |= UInt32(optionKey) }
        if mask.contains(.control) { m |= UInt32(controlKey) }
        if mask.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    // MARK: - CGEventTap path (modifier-only)

    private func installEventTap(for binding: HotkeyBinding) {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { (_, type, event, _) -> Unmanaged<CGEvent>? in
            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
            DispatchQueue.main.async {
                HotkeyManager.sharedInstance?.handleFlagsChanged(event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else {
            Log.hotkey.error("failed to create event tap (need Input Monitoring permission)")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.info("event tap installed for modifier-only binding")
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard let binding = currentBinding, let target = binding.modifierOnly else { return }
        let targetKeyCode = Self.cgKeyCode(for: target)
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == targetKeyCode else { return }

        let active = isModifierActive(for: target, flags: event.flags)
        let now = CFAbsoluteTimeGetCurrent()

        switch binding.trigger {
        case .press:
            if activeMode == .pushToTalk {
                if active && !modifierHeld {
                    modifierHeld = true
                    onPress?()
                } else if !active && modifierHeld {
                    modifierHeld = false
                    onRelease?()
                }
            } else if active {
                onPress?()
            }

        case .doubleTap:
            if !active { return }
            if let last = lastModifierPress, last.key == target, now - last.time < 0.3 {
                lastModifierPress = nil
                onPress?()
            } else {
                lastModifierPress = (target, now)
            }

        case .longPress:
            if active {
                lastModifierPress = (target, now)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, let last = self.lastModifierPress, last.key == target else { return }
                    if CFAbsoluteTimeGetCurrent() - last.time >= 0.5 {
                        self.onPress?()
                        self.lastModifierPress = nil
                    }
                }
            } else {
                lastModifierPress = nil
            }
        }
    }

    private static func cgKeyCode(for mod: HotkeyBinding.ModifierOnly) -> CGKeyCode {
        switch mod {
        case .leftCommand:  return 0x37
        case .rightCommand: return 0x36
        case .leftShift:    return 0x38
        case .rightShift:   return 0x3C
        case .leftOption:   return 0x3A
        case .rightOption:  return 0x3D
        case .leftControl:  return 0x3B
        case .rightControl: return 0x3E
        case .fn:           return 0x3F
        }
    }

    private func isModifierActive(for mod: HotkeyBinding.ModifierOnly, flags: CGEventFlags) -> Bool {
        switch mod {
        case .leftCommand, .rightCommand: return flags.contains(.maskCommand)
        case .leftShift, .rightShift:     return flags.contains(.maskShift)
        case .leftOption, .rightOption:   return flags.contains(.maskAlternate)
        case .leftControl, .rightControl: return flags.contains(.maskControl)
        case .fn:                         return flags.contains(.maskSecondaryFn)
        }
    }
}
