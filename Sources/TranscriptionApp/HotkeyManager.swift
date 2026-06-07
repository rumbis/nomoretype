import Foundation
import Cocoa
import ApplicationServices

// MARK: - Global Hotkey Manager
/// Listens for right Command double-tap to toggle microphone recording.
///
/// Uses CGEvent tap when Accessibility is granted (primary)
/// Falls back to NSEvent local monitor (when our app is frontmost)
/// and periodic AX permission checks.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onToggleRecording: (() -> Void)?

    // Event tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // NSEvent local monitor (when our app is frontmost)
    private var localMonitor: Any?

    // Permission polling
    private var permissionTimer: Timer?
    private weak var permissionPromptWindow: NSWindow?

    // State
    private var lastPressTime: Date?
    private(set) var isRecording = false

    private let doubleTapThreshold: TimeInterval = 0.4
    private let rightCommandKeyCode: UInt16 = 0x36

    // When true, we're using the CGEvent tap
    private(set) var isEventTapActive = false

    private init() {}

    // MARK: - Setup

    func setup() {
        // Always try local monitor (works without permissions when our app is focused)
        startLocalMonitor()

        // Try CGEvent tap
        tryCreateEventTap()

        // Start polling for Accessibility permission
        startPermissionPolling()
    }

    func retrySetup() {
        if !isEventTapActive {
            tryCreateEventTap()
        }
    }

    func setRecordingState(_ recording: Bool) {
        isRecording = recording
    }

    // MARK: - NSEvent Local Monitor

    private func startLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if event.keyCode == self?.rightCommandKeyCode && event.modifierFlags.contains(.command) {
                self?.handleRightCommandPress()
            }
            return event
        }
    }

    // MARK: - CGEvent Tap

    private func tryCreateEventTap() {
        guard !isEventTapActive else { return }

        if !AXIsProcessTrusted() { return }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return mgr.eventTapCallback(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isEventTapActive = true

        print("Hotkey: CGEvent tap ACTIVE")
    }

    private func eventTapCallback(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged,
              event.getIntegerValueField(.keyboardEventKeycode) == rightCommandKeyCode
        else { return Unmanaged.passUnretained(event) }

        // Fires on press only (flagsChanged fires for both press and release)
        // We only care about press events for double-tap detection
        if event.flags.contains(.maskCommand) {
            handleRightCommandPress()
        }

        // Swallow the event so it doesn't reach other apps
        return nil
    }

    // MARK: - Permission Polling

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // If Accessibility was granted, set up the tap
            if !self.isEventTapActive && AXIsProcessTrusted() {
                DispatchQueue.main.async { self.tryCreateEventTap() }
            }
        }
    }

    /// Opens System Settings → Privacy → Accessibility
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Shows a dialog explaining how to grant permission
    func showPermissionGuide() {
        let alert = NSAlert()
        alert.messageText = "Hotkey Needs Accessibility Permission"
        alert.informativeText = """
        To use the double-tap Right Command hotkey globally:

        1. Click "Open Settings" below
        2. Click the 🔒 lock icon to make changes
        3. Click ➕ and add TranscriptionApp
        4. Make sure the checkbox next to it is ✅

        The hotkey will activate automatically once granted.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    // MARK: - Core Logic

    private func handleRightCommandPress() {
        let now = Date()

        if isRecording {
            DispatchQueue.main.async { [weak self] in self?.onToggleRecording?() }
            lastPressTime = nil
        } else {
            if let last = lastPressTime, now.timeIntervalSince(last) < doubleTapThreshold {
                DispatchQueue.main.async { [weak self] in self?.onToggleRecording?() }
                lastPressTime = nil
            } else {
                lastPressTime = now
            }
        }
    }

    // MARK: - Cleanup

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil

        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }

        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes) }
        eventTap = nil; runLoopSource = nil; isEventTapActive = false
    }

    deinit { stop() }
}
