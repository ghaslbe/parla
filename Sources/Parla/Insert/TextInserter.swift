import AppKit
import CoreGraphics

/// Inserts transcribed text into whatever app currently has focus.
/// Requires the **Accessibility** permission (to post synthetic key events).
enum TextInserter {

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the system Accessibility dialog if not yet trusted.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func insert(_ text: String, method: InsertMethod) {
        guard !text.isEmpty else { return }
        switch method {
        case .unicode: typeUnicode(text)
        case .paste:   paste(text)
        }
    }

    // MARK: - Direct Unicode typing (does not touch the clipboard)

    private static func typeUnicode(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        // CGEvent's unicode payload is capped per event, so chunk it.
        for chunk in text.chunked(by: 20) {
            let utf16 = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
            utf16.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - Clipboard + ⌘V

    private static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // 'v'
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)
        vUp?.post(tap: .cgSessionEventTap)

        // Restore the previous clipboard once the paste has been consumed.
        if let saved {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pb.clearContents()
                pb.setString(saved, forType: .string)
            }
        }
    }
}

private extension String {
    func chunked(by size: Int) -> [String] {
        guard size > 0, count > size else { return [self] }
        var result: [String] = []
        var idx = startIndex
        while idx < endIndex {
            let end = index(idx, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[idx..<end]))
            idx = end
        }
        return result
    }
}
