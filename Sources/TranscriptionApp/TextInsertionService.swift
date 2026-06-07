import Foundation
import Cocoa

// MARK: - Text Insertion Service
/// Inserts transcribed text into the currently focused application.
/// Uses subprocess for AppleScript (crash-safe) + AX as fallback.
final class TextInsertionService {
    static let shared = TextInsertionService()

    private init() {}

    /// Inserts text at the current cursor position.
    func insertText(_ text: String) {
        guard !text.isEmpty else {
            print("TextIns: empty text, skipping")
            return
        }

        // 1) Try Accessibility API (fast, no clipboard pollution)
        if insertViaAccessibility(text) {
            print("TextIns: via AX")
            return
        }

        // 2) Pasteboard + osascript subprocess (crash-safe)
        insertViaSubprocess(text)
    }

    // MARK: - Accessibility API (needs permission)

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        return autoreleasepool {
            let systemWide = AXUIElementCreateSystemWide()

            var focusedApp: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
                  let app = focusedApp
            else { return false }

            let appElement = app as! AXUIElement

            var focusedElement: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
                  let element = focusedElement
            else { return false }

            let uiElement = element as! AXUIElement

            // Try value attribute (text fields)
            if AXUIElementSetAttributeValue(uiElement, kAXValueAttribute as CFString, text as CFTypeRef) == .success {
                return true
            }

            // Try selected text (rich text)
            if AXUIElementSetAttributeValue(uiElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
                return true
            }

            return false
        }
    }

    // MARK: - Pasteboard + osascript subprocess (crash-safe)

    private func insertViaSubprocess(_ text: String) {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Run AppleScript as a SEPARATE PROCESS — if it crashes, our app stays alive
        let script = """
        activate application (path to frontmost application as text)
        delay 0.05
        tell application "System Events" to keystroke "v" using command down
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                print("TextIns: osascript exited with status \(task.terminationStatus)")
            }
        } catch {
            print("TextIns: osascript launch failed: \(error.localizedDescription)")
        }

        // Restore original pasteboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [savedItems] in
            autoreleasepool {
                pasteboard.clearContents()
                if let items = savedItems {
                    pasteboard.writeObjects(items)
                }
            }
        }
    }
}
