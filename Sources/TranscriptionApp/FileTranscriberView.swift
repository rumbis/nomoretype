import SwiftUI
import UniformTypeIdentifiers

// MARK: - File Transcriber View
struct FileTranscriberView: View {
    @StateObject private var vm = AppViewModel.shared
    @State private var isDropTargeted = false
    @State private var selectedLanguage: LanguageOption = LanguageOption.all.first { $0.id == "auto" } ?? LanguageOption.all[0]
    @State private var isFilePickerPresented = false
    @State private var outputFormat: OutputFormat = .text

    @State private var processingAction = false
    @State private var llmResult: String?

    private let supportedTypes: [UTType] = [
        .audio, .mpeg, .wav,
        UTType(filenameExtension: "mp3") ?? .audio,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "ogg") ?? .audio,
        UTType(filenameExtension: "flac") ?? .audio,
        UTType(filenameExtension: "webm") ?? .movie,
        UTType(filenameExtension: "mp4") ?? .movie,
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("Transcribe Audio File")
                .font(.title2).fontWeight(.semibold)

            // Language + Format row
            HStack(spacing: 20) {
                HStack {
                    Text("Language:").foregroundColor(.secondary)
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(LanguageOption.all) { lang in
                            Text("\(lang.flag) \(lang.name)").tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                HStack {
                    Text("Format:").foregroundColor(.secondary)
                    Picker("Format", selection: $outputFormat) {
                        ForEach(OutputFormat.allCases) { fmt in
                            Label(fmt.label, systemImage: fmt.icon).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            Spacer()

            switch vm.fileState {
            case .idle:
                dropZone

            case .transcribing:
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("Transcribing...").font(.headline).foregroundColor(.secondary)
                    Text("May take a moment for longer files")
                        .font(.caption).foregroundColor(.secondary)
                }

            case .done(let result):
                resultView(result)

            case .error(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(msg).foregroundColor(.red).multilineTextAlignment(.center)
                    Button("Try Again") { vm.resetFileState() }
                }
            }

            Spacer()
        }
        .padding()
        .onDrop(of: supportedTypes, isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Drop Zone
    private var dropZone: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDropTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                    )
                    .frame(maxWidth: 500, minHeight: 200)

                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 36))
                        .foregroundColor(isDropTargeted ? .accentColor : .secondary)
                    Text("Drop audio/video file here").font(.headline)
                    Text("or")
                    Button("Select File...") {
                        isFilePickerPresented = true
                    }
                    .buttonStyle(.bordered)
                    .fileImporter(isPresented: $isFilePickerPresented, allowedContentTypes: supportedTypes, allowsMultipleSelection: false) { result in
                        switch result {
                        case .success(let urls):
                            vm.transcribeFile(urls: urls, language: selectedLanguage.id)
                        case .failure(let error):
                            vm.fileState = .error(error.localizedDescription)
                        }
                    }
                    Text("MP3, M4A, WAV, FLAC, OGG, MP4, WebM, MPEG")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Result View
    private func resultView(_ result: TranscriptionResult) -> some View {
        VStack(spacing: 12) {
            // Toolbar
            HStack {
                Text(outputFormat.label)
                    .font(.headline)
                Text("(\(result.segments.count) segments)")
                    .font(.caption).foregroundColor(.secondary)

                Spacer()

                // Copy button
                Button {
                    vm.copyToPasteboard(formattedContent(result))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                // Save SRT button
                if outputFormat == .srt {
                    Button {
                        saveSRT(result.srt)
                    } label: {
                        Label("Save .srt", systemImage: "square.and.arrow.down")
                    }
                }

                // LLM Actions
                if outputFormat == .text && !processingAction {
                    Button {
                        Task {
                            processingAction = true
                            llmResult = await vm.polishTranscription(text: result.text)
                            processingAction = false
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .help("Polish transcription")

                    Menu {
                        ForEach(TranslationLanguage.supported, id: \.code) { lang in
                            Button("\(lang.flag) \(lang.name)") {
                                Task {
                                    processingAction = true
                                    llmResult = await vm.translateTranscription(text: result.text, to: lang.name)
                                    processingAction = false
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "translate")
                    }
                    .help("Translate to...")
                }

                Button("New") { vm.resetFileState() }
            }
            .padding(.horizontal)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    switch outputFormat {
                    case .text:
                        Text(result.text)
                            .textSelection(.enabled)
                            .padding()

                    case .srt:
                        Text(result.srt)
                            .textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                            .padding()

                    case .segments:
                        ForEach(result.segments, id: \.id) { seg in
                            SegmentRow(segment: seg)
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))

            // LLM result (Polish / Translate)
            if let llmText = llmResult {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: llmText.hasPrefix("❌") ? "exclamationmark.triangle" : "checkmark.seal")
                            .foregroundColor(llmText.hasPrefix("❌") ? .orange : .accentColor)
                        Text(llmText.hasPrefix("❌") ? "Error" : "Result")
                            .font(.headline)
                        Spacer()
                        Button {
                            vm.copyToPasteboard(llmText)
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button("Clear") { llmResult = nil }
                    }
                    ScrollView {
                        Text(llmText)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)
            }

            if processingAction {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Processing...").foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    private func formattedContent(_ result: TranscriptionResult) -> String {
        switch outputFormat {
        case .text:  return result.text
        case .srt:   return result.srt
        case .segments: return result.segmentedText
        }
    }

    private func saveSRT(_ content: String) {
        let panel = NSSavePanel()
        panel.title = "Save SRT Subtitles"
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "transcript.srt"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Drop
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: tempURL)
            Task { @MainActor in
                vm.transcribeFile(urls: [tempURL], language: selectedLanguage.id)
            }
        }
        return true
    }
}

// MARK: - Segment Row
struct SegmentRow: View {
    let segment: TranscriptionResult.Segment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            VStack(alignment: .trailing, spacing: 0) {
                Text(timestamp(segment.start))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.accentColor)
                Text(timestamp(segment.end))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 52)

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 2)

            // Segment text
            Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func timestamp(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 10)
        return "\(m):\(String(format: "%02d", s)).\(ms)"
    }
}

// MARK: - Translation Target Languages
struct TranslationLanguage {
    let code: String
    let name: String
    let flag: String

    static let supported: [TranslationLanguage] = [
        TranslationLanguage(code: "en", name: "English", flag: "🇺🇸"),
        TranslationLanguage(code: "el", name: "Greek", flag: "🇬🇷"),
        TranslationLanguage(code: "es", name: "Spanish", flag: "🇪🇸"),
        TranslationLanguage(code: "fr", name: "French", flag: "🇫🇷"),
        TranslationLanguage(code: "de", name: "German", flag: "🇩🇪"),
        TranslationLanguage(code: "it", name: "Italian", flag: "🇮🇹"),
        TranslationLanguage(code: "pt", name: "Portuguese", flag: "🇵🇹"),
        TranslationLanguage(code: "ru", name: "Russian", flag: "🇷🇺"),
        TranslationLanguage(code: "ja", name: "Japanese", flag: "🇯🇵"),
        TranslationLanguage(code: "ko", name: "Korean", flag: "🇰🇷"),
        TranslationLanguage(code: "zh", name: "Chinese", flag: "🇨🇳"),
        TranslationLanguage(code: "ar", name: "Arabic", flag: "🇸🇦"),
        TranslationLanguage(code: "tr", name: "Turkish", flag: "🇹🇷"),
        TranslationLanguage(code: "nl", name: "Dutch", flag: "🇳🇱"),
        TranslationLanguage(code: "pl", name: "Polish", flag: "🇵🇱"),
    ]
}
