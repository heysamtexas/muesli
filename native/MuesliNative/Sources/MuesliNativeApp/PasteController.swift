import AppKit
import ApplicationServices
import Foundation
import MuesliCore

enum PasteController {
    static func paste(text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
        }
    }

    private static func simulatePaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            fputs("[muesli-native] failed to create event source for paste\n", stderr)
            return
        }
        let keyCode: CGKeyCode = 9 // V
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        commandDown?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        commandUp?.flags = .maskCommand
        commandDown?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }
}
