import AppKit
import CoreGraphics
import IOKit.hid

/// Watches the keyboard for the configured trigger key using a CGEventTap.
///
/// This requires the **Input Monitoring** permission. In push-to-talk mode it
/// fires `onPress` when the key goes down and `onRelease` when it comes up; in
/// toggle mode it fires `onToggle` on each key-down.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onToggle: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false

    /// Maps a trigger key's CGKeyCode to the modifier flag it sets.
    private static func flag(for key: TriggerKey) -> CGEventFlags {
        switch key {
        case .rightOption:  return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .fn:           return .maskSecondaryFn
        }
    }

    /// Whether the process currently holds Input Monitoring access.
    static var hasInputMonitoring: Bool {
        // kIOHIDRequestTypeListenEvent == 1
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func start() {
        guard tap == nil else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: refcon) else {
            NSLog("Parla: could not create event tap (Input Monitoring not granted?)")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        keyIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }

        let trigger = AppSettings.shared.trigger
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keycode == trigger.rawValue else { return }

        let flag = Self.flag(for: trigger)
        let isDown = event.flags.contains(flag)

        // Deliver on the main thread; callbacks touch UI/audio.
        if AppSettings.shared.holdToTalk {
            if isDown && !keyIsDown {
                keyIsDown = true
                DispatchQueue.main.async { [weak self] in self?.onPress?() }
            } else if !isDown && keyIsDown {
                keyIsDown = false
                DispatchQueue.main.async { [weak self] in self?.onRelease?() }
            }
        } else {
            // Toggle mode: act on each key-down only.
            if isDown && !keyIsDown {
                keyIsDown = true
                DispatchQueue.main.async { [weak self] in self?.onToggle?() }
            } else if !isDown {
                keyIsDown = false
            }
        }
    }
}
