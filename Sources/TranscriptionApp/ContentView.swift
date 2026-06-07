import SwiftUI
import AppKit

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var vm = AppViewModel.shared

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    if !HotkeyManager.shared.isEventTapActive {
                        HotkeyManager.shared.showPermissionGuide()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(HotkeyManager.shared.isEventTapActive ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(HotkeyManager.shared.isEventTapActive ? "Hotkey Active" : "Grant Access")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(HotkeyManager.shared.isEventTapActive
                    ? "Global hotkey active — double-tap Right Command"
                    : "Click to grant Accessibility permission for global hotkey")
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        List(selection: $vm.selectedTab) {
            Label("File Transcribe", systemImage: "waveform")
                .tag(AppViewModel.Tab.file)
            Label("Mic Transcribe", systemImage: "mic")
                .tag(AppViewModel.Tab.mic)
            Label("History", systemImage: "clock")
            Label("YouTube", systemImage: "video.bubble")
                .tag(AppViewModel.Tab.youtube)
                .tag(AppViewModel.Tab.history)
            Divider()
            Label("Settings", systemImage: "gear")
                .tag(AppViewModel.Tab.settings)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }

    // MARK: - Detail
    @ViewBuilder
    private var detailView: some View {
        switch vm.selectedTab {
        case .file:  FileTranscriberView()
        case .mic:   MicTranscribeView()
        case .history: HistoryView()
        case .settings: SettingsView()
        case .youtube: YouTubeView()
        }
    }
}

// MARK: - Mic Transcribe View
struct MicTranscribeView: View {
    @StateObject private var vm = AppViewModel.shared
    @AppStorage(SettingsKeys.defaultLanguage) private var micLanguage: String = "auto"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Language picker (always visible)
            HStack(spacing: 8) {
                Text("Language:")
                    .foregroundColor(.secondary)
                Picker("", selection: $micLanguage) {
                    ForEach(LanguageOption.all) { lang in
                        HStack {
                            Text(lang.flag)
                            Text(lang.name)
                        }.tag(lang.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            // Icon & status
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(micIconColor)

            Text(micStatusText)
                .font(.title2)
                .fontWeight(.medium)

            if case .recording = vm.micState {
                Text(durationString)
                    .font(.system(.title, design: .monospaced))
                    .foregroundColor(.secondary)
                LevelBar(level: vm.micLevel)
                    .frame(width: 200, height: 8)
            }

            if case .error(let msg) = vm.micState {
                VStack(spacing: 8) {
                    Text(msg).foregroundColor(.red).multilineTextAlignment(.center)
                    Button("Dismiss") { vm.micState = .idle }
                }
            }

            if case .transcribing = vm.micState {
                ProgressView().scaleEffect(1.2)
                Text("Transcribing...").foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Double-tap Right Command to start recording", systemImage: "command")
                Label("Tap once to stop and transcribe", systemImage: "stop.circle")
                Label("Text is automatically inserted at cursor", systemImage: "text.cursor")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 40)
        }
        .padding()
    }

    private var micIconColor: Color {
        switch vm.micState {
        case .recording: return .red
        case .transcribing: return .orange
        case .idle: return .secondary
        case .error: return .red
        }
    }

    private var micStatusText: String {
        switch vm.micState {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .error: return "Error"
        }
    }

    private var durationString: String {
        let total = Int(vm.recordingDuration)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
    }
}
