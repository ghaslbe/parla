import AppKit

/// A small floating indicator shown near the bottom of the screen while Parla
/// is listening or transcribing. Non-activating, so it never steals focus from
/// the app you are dictating into.
final class PillWindow {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = NSView(frame: panel.contentView!.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.92).cgColor
        container.layer?.cornerRadius = 22
        container.autoresizingMask = [.width, .height]

        dot.frame = NSRect(x: 18, y: 17, width: 10, height: 10)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor

        label.frame = NSRect(x: 38, y: 12, width: 130, height: 20)
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false

        container.addSubview(dot)
        container.addSubview(label)
        panel.contentView?.addSubview(container)
    }

    enum State {
        case listening
        case transcribing
        case error(String)
    }

    func show(_ state: State) {
        switch state {
        case .listening:
            label.stringValue = "Listening…"
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            startPulse()
        case .transcribing:
            label.stringValue = "Transcribing…"
            dot.layer?.backgroundColor = NSColor.systemYellow.cgColor
            stopPulse()
        case .error(let msg):
            label.stringValue = String(msg.prefix(22))
            dot.layer?.backgroundColor = NSColor.systemGray.cgColor
            stopPulse()
        }
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        stopPulse()
        panel.orderOut(nil)
    }

    func flashError(_ msg: String) {
        show(.error(msg))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.hide() }
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let w = panel.frame.width
        let x = v.midX - w / 2
        let y = v.minY + 90
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startPulse() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.3
        anim.duration = 0.6
        anim.autoreverses = true
        anim.repeatCount = .infinity
        dot.layer?.add(anim, forKey: "pulse")
    }

    private func stopPulse() {
        dot.layer?.removeAnimation(forKey: "pulse")
    }
}
