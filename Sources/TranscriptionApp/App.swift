import SwiftUI
import AppKit
import Combine

@main
struct TranscriptionAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    // Keep app alive for hotkey when window closes
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Recording") {
                Button("Toggle Microphone") {
                    Task { @MainActor in
                        AppViewModel.shared.toggleMicRecording()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Stop & Cancel") {
                    Task { @MainActor in
                        AppViewModel.shared.cancelMicRecording()
                    }
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the shared AppViewModel (starts hotkey listener)
        _ = AppViewModel.shared

        // Prevent app from quitting when last window closes
        NSApp.setActivationPolicy(.regular)

        // Setup menu bar icon
        setupMenuBar()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        HotkeyManager.shared.retrySetup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        OverlayWindowManager.shared.reposition()
    }

    // MARK: - Menu Bar

    @MainActor
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateStatusIcon()

        statusItem?.button?.action = #selector(statusItemClicked)
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @MainActor
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleWindow()
        }
    }

    @MainActor private func showMenu() {
        let isRecording = AppViewModel.shared.micState == .recording
        let menu = NSMenu()

        let titleItem = NSMenuItem(
            title: isRecording ? "🔴 Recording..." : "🎙️ TranscriptionApp",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(
            title: isRecording ? "⏹  Stop Recording" : "🎤  Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggleItem)

        if isRecording {
            let cancelItem = NSMenuItem(
                title: "✕  Cancel",
                action: #selector(cancelRecording),
                keyEquivalent: "."
            )
            cancelItem.keyEquivalentModifierMask = .command
            menu.addItem(cancelItem)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Show Window",
            action: #selector(showWindow),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "About TranscriptionApp",
            action: #selector(showAbout),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleRecording() {
        Task { @MainActor in
            AppViewModel.shared.toggleMicRecording()
            updateStatusIcon()
        }
    }

    @objc private func cancelRecording() {
        Task { @MainActor in
            AppViewModel.shared.cancelMicRecording()
            updateStatusIcon()
        }
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @MainActor private func updateStatusIcon() {
        let isRecording = AppViewModel.shared.micState == .recording
        statusItem?.button?.title = isRecording ? "🔴" : "🎙️"
        statusItem?.button?.needsDisplay = true
    }

    private func toggleWindow() {
        if let window = NSApp.windows.first, window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }
}
