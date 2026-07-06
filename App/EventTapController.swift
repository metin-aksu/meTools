import Cocoa
import ApplicationServices

/// Intercepts keyboard shortcuts while Finder is frontmost and remaps them
/// according to the user's feature toggles:
///
///   Return / keypad Enter → Cmd+Down  (open the selection)
///   F2                    → Return    (rename the selection)
///   Ctrl+C                → Cmd+C     (copy)
///   Ctrl+X                → Cmd+C, remembered as a cut
///   Ctrl+V                → Cmd+V, or Cmd+Opt+V after a cut (move)
///   Ctrl+Z                → Cmd+Z     (undo)
final class EventTapController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Whether the last Ctrl+X is still waiting for its Ctrl+V.
    private var pendingCut = false

    /// True when the tap exists and is currently enabled.
    var isRunning: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private let finderBundleID = "com.apple.finder"

    private enum Key {
        static let returnKey: CGKeyCode = 36
        static let keypadEnter: CGKeyCode = 76
        static let downArrow: CGKeyCode = 125
        static let f2: CGKeyCode = 120
        static let backspace: CGKeyCode = 51
        static let c: CGKeyCode = 8
        static let v: CGKeyCode = 9
        static let x: CGKeyCode = 7
        static let z: CGKeyCode = 6
    }

    /// Marker stamped onto events we inject ourselves, so the tap lets them
    /// through instead of remapping them again (e.g. the Return injected for
    /// F2-rename must not be turned into Cmd+Down by the Return feature).
    private let injectedMarker: Int64 = 0x6D65_546F // "meTo"

    func start() {
        if isRunning { return }

        // Tear down any stale tap before recreating.
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("meTools: event tap oluşturulamadı — Erişilebilirlik izni verilmiş mi?")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables the tap if the callback is too slow; just re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // Let our own synthetic events through untouched.
        if event.getIntegerValueField(.eventSourceUserData) == injectedMarker {
            return Unmanaged.passUnretained(event)
        }

        guard isFinderFrontmost() else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let defaults = MTSettings.defaults
        let mods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let activeMods = event.flags.intersection(mods)

        switch keyCode {
        case Key.returnKey, Key.keypadEnter:
            guard defaults.bool(forKey: MTSettings.returnOpens), activeMods.isEmpty else { break }
            // If a text field has focus (inline rename, search, save dialog),
            // let Return commit normally.
            if isEditingText() { break }
            inject(key: Key.downArrow, flags: .maskCommand)
            return nil

        case Key.f2:
            guard defaults.bool(forKey: MTSettings.f2Rename), activeMods.isEmpty else { break }
            if isEditingText() { break }
            // Plain Return starts inline rename in Finder; the injected marker
            // keeps our own Return feature from remapping it.
            inject(key: Key.returnKey, flags: [])
            return nil

        case Key.backspace:
            guard defaults.bool(forKey: MTSettings.backspaceDeletes), activeMods.isEmpty else { break }
            if isEditingText() { break }
            // Cmd+Backspace is Finder's "Move to Trash".
            inject(key: Key.backspace, flags: .maskCommand)
            return nil

        case Key.c:
            guard defaults.bool(forKey: MTSettings.ctrlCCopies), activeMods == .maskControl else { break }
            if isEditingText() { break }
            pendingCut = false
            inject(key: Key.c, flags: .maskCommand)
            return nil

        case Key.x:
            guard defaults.bool(forKey: MTSettings.ctrlXCuts), activeMods == .maskControl else { break }
            if isEditingText() { break }
            // Finder cuts by copying first; the paste then moves with Cmd+Opt+V.
            pendingCut = true
            inject(key: Key.c, flags: .maskCommand)
            return nil

        case Key.v:
            guard defaults.bool(forKey: MTSettings.ctrlVPastes), activeMods == .maskControl else { break }
            if isEditingText() { break }
            if pendingCut {
                pendingCut = false
                inject(key: Key.v, flags: [.maskCommand, .maskAlternate])
            } else {
                inject(key: Key.v, flags: .maskCommand)
            }
            return nil

        case Key.z:
            guard defaults.bool(forKey: MTSettings.ctrlZUndoes), activeMods == .maskControl else { break }
            if isEditingText() { break }
            inject(key: Key.z, flags: .maskCommand)
            return nil

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func isFinderFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderBundleID
    }

    /// True when the focused UI element is an editable text control.
    private func isEditingText() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let appElement = AXUIElementCreateApplication(pid)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else {
            return false
        }
        let element = focused as! AXUIElement

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }

        return role == (kAXTextFieldRole as String)
            || role == (kAXTextAreaRole as String)
            || role == (kAXComboBoxRole as String)
    }

    /// Posts a synthetic keystroke, stamped so our own tap ignores it.
    private func inject(key: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.userData = injectedMarker

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        for event in [keyDown, keyUp] {
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: injectedMarker)
        }
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
