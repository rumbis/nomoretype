import Foundation
import AppKit
import SwiftUI
import AVFoundation

// MARK: - Central ViewModel
@MainActor
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()

    // MARK: - State
    enum MicState: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    enum FileState {
        case idle
        case transcribing
        case done(TranscriptionResult)
        case error(String)
    }

    @Published var micState: MicState = .idle
    @Published var fileState: FileState = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var micLevel: Float = 0
    @Published var hasAccessibilityPermission = false
    @Published var hasMicrophonePermission = false
    @Published var selectedTab: Tab = .file

    enum Tab: String, CaseIterable {
        case file = "File"
        case mic = "Mic"
        case history = "History"
        case youtube = "YouTube"
    case settings = "Settings"
    }

    // MARK: - Services
    private let audioCapture = AudioCaptureService()
    private let hotkeyManager = HotkeyManager.shared
    private let groqService = GroqService.shared
    private let textInserter = TextInsertionService.shared
    private let historyStore = HistoryStore.shared

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var levelTimer: Timer?

    private init() {
        setupHotkey()
        checkPermissions()
    }

    // MARK: - Setup

    private func setupHotkey() {
        hotkeyManager.onToggleRecording = { [weak self] in
            Task { @MainActor in
                self?.toggleMicRecording()
            }
        }
        hotkeyManager.setup()
    }

    private func checkPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        Task {
            hasMicrophonePermission = await AudioCaptureService.requestPermission()
        }
    }

    // MARK: - Microphone Recording (Hotkey)

    func toggleMicRecording() {
        switch micState {
        case .idle:
            startMicRecording()
        case .recording:
            stopMicTranscribe()
        case .transcribing:
            break // ignore
        case .error:
            micState = .idle
            startMicRecording()
        }
    }

    func startMicRecording() {
        // Check API key
        guard !(UserDefaults.standard.string(forKey: SettingsKeys.groqApiKey) ?? "").isEmpty else {
            micState = .error("Set your Groq API key in Settings first.")
            return
        }

        // Check mic permission
        guard hasMicrophonePermission else {
            Task {
                hasMicrophonePermission = await AudioCaptureService.requestPermission()
                if hasMicrophonePermission {
                    _startRecording()
                } else {
                    micState = .error("Microphone access denied. Enable it in System Settings.")
                }
            }
            return
        }

        _startRecording()
    }

    private func _startRecording() {
        guard audioCapture.startRecording() else {
            micState = .error("Failed to start recording.")
            return
        }

        micState = .recording
        hotkeyManager.setRecordingState(true)
        recordingStartTime = Date()
        recordingDuration = 0

        // Duration timer
        durationTimer?.invalidate()
        let startTime = recordingStartTime
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let start = startTime else { return }
            Task { @MainActor in
                self?.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        // Level meter
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let level = self.audioCapture.averagePower()
            Task { @MainActor in
                self.micLevel = level
            }
        }

        // Show overlay window
        OverlayWindowManager.shared.show()

        print("Mic: recording started")
    }

    func stopMicTranscribe() {
        guard let audioURL = audioCapture.stopRecording() else {
            micState = .error("No recording data.")
            return
        }

        // Hide active bar immediately on single press
        micState = .transcribing
        hotkeyManager.setRecordingState(false)
        durationTimer?.invalidate()
        levelTimer?.invalidate()
        OverlayWindowManager.shared.hide()

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        recordingDuration = duration

        Task {
            do {
                let language = UserDefaults.standard.string(forKey: SettingsKeys.defaultLanguage) ?? "auto"
                let langCode = language == "auto" ? nil : language

                let text = try await groqService.transcribe(audioURL: audioURL, language: langCode)

                await MainActor.run {
                    textInserter.insertText(text)
                    micState = .idle

                    // Save to history
                    let item = TranscriptionItem(
                        id: UUID(),
                        text: text,
                        language: language == "auto" ? nil : language,
                        source: .microphone,
                        timestamp: Date(),
                        duration: duration,
                        fileName: nil
                    )
                    historyStore.add(item)

                    print("Mic: transcribed '\(text.prefix(50))...'")
                }
            } catch {
                await MainActor.run {
                    micState = .error(error.localizedDescription)
                    print("Mic: error \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelMicRecording() {
        _ = audioCapture.stopRecording()
        micState = .idle
        hotkeyManager.setRecordingState(false)
        durationTimer?.invalidate()
        levelTimer?.invalidate()
        OverlayWindowManager.shared.hide()
    }

    // MARK: - File Transcription

    func transcribeFile(urls: [URL], language: String?) {
        guard let url = urls.first else { return }
        
        // Check API key
        guard !(UserDefaults.standard.string(forKey: SettingsKeys.groqApiKey) ?? "").isEmpty else {
            fileState = .error("Set your Groq API key in Settings first.")
            return
        }

        fileState = .transcribing

        Task {
            do {
                let langCode = (language == nil || language == "auto") ? nil : language
                let result = try await groqService.transcribeWithSegments(audioURL: url, language: langCode)

                await MainActor.run {
                    fileState = .done(result)

                    // Save to history
                    let item = TranscriptionItem(
                        id: UUID(),
                        text: result.text,
                        language: language == "auto" ? nil : language,
                        source: .file,
                        timestamp: Date(),
                        duration: nil,
                        fileName: url.lastPathComponent
                    )
                    historyStore.add(item)
                }
            } catch {
                await MainActor.run {
                    fileState = .error(error.localizedDescription)
                }
            }
        }
    }

    func resetFileState() {
        fileState = .idle
    }

    // MARK: - Copy / Action Helpers

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - LLM Actions (Polish / Translate)

    func polishTranscription(text: String) async -> String {
        do {
            return try await LLMService.shared.polish(text: text)
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }

    func translateTranscription(text: String, to language: String) async -> String {
        do {
            return try await LLMService.shared.translate(text: text, to: language)
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }
}

// MARK: - Overlay Window Manager
@MainActor
final class OverlayWindowManager {
    static let shared = OverlayWindowManager()

    private var window: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?

    private init() {}

    func show() {
        if window == nil {
            let overlayView = OverlayView()
            hostingView = NSHostingView(rootView: overlayView)
            hostingView?.setFrameSize(NSSize(width: 200, height: 36))

            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: hostingView!.bounds.size),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.hasShadow = true
            panel.hidesOnDeactivate = false

            positionPanel(panel)
            self.window = panel
        }

        positionPanel(window!)
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionPanel(_ panel: NSPanel) {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 30
            )
            panel.setFrameOrigin(origin)
        }
    }

    func reposition() {
        guard let panel = window else { return }
        positionPanel(panel)
    }
}

// MARK: - Overlay SwiftUI View
struct OverlayView: View {
    @StateObject private var vm = AppViewModel.shared
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        if case .recording = vm.micState {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulseOpacity)

                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))

                Text(durationString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .onAppear {
                pulseOpacity = 0.3
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.3
                }
            }
        }
    }

    private var durationString: String {
        let total = Int(vm.recordingDuration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
    }
}

// MARK: - Level Bar
struct LevelBar: View {
    let level: Float // 0–1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: geo.size.width)

                RoundedRectangle(cornerRadius: 3)
                    .fill(levelColor)
                    .frame(width: max(2, geo.size.width * CGFloat(level)))
            }
        }
    }

    private var levelColor: Color {
        if level > 0.7 { return .red }
        if level > 0.4 { return .orange }
        return .green
    }
}
