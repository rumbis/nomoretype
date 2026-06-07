import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - YouTube View
struct YouTubeView: View {
    @State private var videoURL: String = ""
    @State private var language: String = "en"
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var transcriptionResult: TranscriptionResult?
    @State private var videoTitle: String?
    @State private var useGroqFallback = false
    @State private var hasSubtitles = false
    @State private var logLines: [String] = []
    @State private var outputFormat: OutputFormat = .srt
    @State private var processingAction = false
    @State private var llmResult: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("YouTube Transcription")
                .font(.title2).fontWeight(.semibold)

            // URL Input
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.secondary)
                    TextField("Paste YouTube URL...", text: $videoURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                HStack(spacing: 12) {
                    Text("Subtitle language:")
                        .foregroundColor(.secondary)
                    Picker("", selection: $language) {
                        Text("English (en)").tag("en")
                        Text("Greek (el)").tag("el")
                        Text("Auto-generated").tag("auto")
                        ForEach(LanguageOption.all.filter { $0.id != "auto" }, id: \.id) { lang in
                            Text("\(lang.flag) \(lang.name) (\(lang.id))").tag(lang.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Toggle("Groq fallback", isOn: $useGroqFallback)
                        .toggleStyle(.checkbox)
                        .help("If no subtitles found, download audio + transcribe with Groq")
                }
            }
            .padding(.horizontal)

            // Format Picker (always visible, like File tab)
            HStack(spacing: 20) {
                HStack {
                    Text("Format:").foregroundColor(.secondary)
                    Picker("Format", selection: $outputFormat) {
                        ForEach(OutputFormat.allCases) { fmt in
                            Label(fmt.label, systemImage: fmt.icon).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                Spacer()
            }
            .padding(.horizontal)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    fetchTranscript()
                } label: {
                    Label("Get Transcript", systemImage: "captions.bubble")
                }
                .buttonStyle(.borderedProminent)
                .disabled(videoURL.isEmpty || isLoading)

                Button("Clear") {
                    videoURL = ""
                    transcriptionResult = nil
                    statusMessage = nil
                    videoTitle = nil
                    logLines = []
                    llmResult = nil
                }
                .disabled(isLoading)

                Spacer()

                if let result = transcriptionResult {
                    Button {
                        copyToPasteboard(formattedContent(result))
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    if outputFormat == .srt {
                        Button {
                            saveSRT(result.srt)
                        } label: {
                            Label("Save .srt", systemImage: "square.and.arrow.down")
                        }
                    }

                    if outputFormat == .text && !processingAction {
                        Button {
                            Task {
                                processingAction = true
                                llmResult = await AppViewModel.shared.polishTranscription(text: result.text)
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
                                        llmResult = await AppViewModel.shared.translateTranscription(text: result.text, to: lang.name)
                                        processingAction = false
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "translate")
                        }
                        .help("Translate to...")
                    }
                }
            }
            .padding(.horizontal)

            // Status / Progress
            if isLoading {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text(statusMessage ?? "Working...").foregroundColor(.secondary)
                }
            }

            if let title = videoTitle {
                HStack {
                    Image(systemName: "music.note")
                    Text(title).font(.headline).lineLimit(1)
                }
                .padding(.horizontal)
            }

            // Log lines
            if !logLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxHeight: 80)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }

            // Result area
            if let result = transcriptionResult {
                VStack(spacing: 8) {
                    // Segment count
                    HStack {
                        Text(outputFormat.label)
                            .font(.headline)
                        Text("(\(outputFormat == .segments ? String(groupedSegments(result.segments).count) : String(result.segments.count)) segments)")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
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
                                let grouped = groupedSegments(result.segments)
                                Text("Showing \(grouped.count) groups (~20s each)")
                                    .font(.caption).foregroundColor(.secondary)
                                    .padding(.horizontal)
                                ForEach(Array(grouped.enumerated()), id: \.offset) { index, seg in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Τμήμα \(index + 1)")
                                            .font(.caption).fontWeight(.semibold)
                                            .foregroundColor(.accentColor)
                                            .padding(.leading, 4)
                                        SegmentRow(segment: seg)
                                    }
                                    .padding(.bottom, 4)
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
                                    AppViewModel.shared.copyToPasteboard(llmText)
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
            } else if !isLoading {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "video.bubble")
                        .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.5))
                    Text("Paste a YouTube URL and tap Get Transcript")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                Spacer()
            }
        }
        .padding(.vertical)
    }

    // MARK: - Fetch Transcript

    private func fetchTranscript() {
        guard !videoURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isLoading = true
        statusMessage = "Fetching video info..."
        transcriptionResult = nil
        videoTitle = nil
        hasSubtitles = false
        logLines = []
        llmResult = nil

        Task {
            await downloadTranscript()
            await MainActor.run { isLoading = false }
        }
    }

    private func downloadTranscript() async {
        let url = videoURL.trimmingCharacters(in: .whitespaces)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("youtube_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Step 1: Get video info
        await appendLog("Fetching video info...")
        let info = try? await runYTLDProbe(url, tmpDir)
        guard let videoInfo = info else {
            await showError("Failed to fetch video info. Check the URL.")
            return
        }
        await setTitle(videoInfo.title)
        await appendLog("Video: \(videoInfo.title)")
        await appendLog("Duration: \(videoInfo.duration)s")
        await appendLog("Available subs: \(videoInfo.availableSubs.joined(separator: ", "))")

        // Step 2: Try to download existing subtitles
        let subLang = language == "auto" ? nil : language
        let targetLang = subLang ?? "en"
        await setStatus("Downloading subtitles (\(targetLang))...")

        let subResult = try? await runYTDLSRT(url, tmpDir, lang: targetLang)
        if let srtContent = subResult, !srtContent.isEmpty {
            let parsed = parseSRT(srtContent)
            await setResult(parsed, hasSubtitles: true)
            await appendLog("✅ Subtitles downloaded successfully!")
            return
        }

        // Step 3: Fallback — download audio + transcribe with Groq
        if useGroqFallback {
            await appendLog("No subtitles found. Falling back to Groq transcription...")
            await setStatus("Downloading audio...")
            let audioURL = try? await downloadAudio(url, tmpDir)
            guard let audio = audioURL else {
                await showError("Failed to download audio.")
                return
            }
            await appendLog("Audio downloaded: \(audio.lastPathComponent)")

            await setStatus("Transcribing with Groq...")
            do {
                let apiLang = language == "auto" ? nil : language
                let result = try await GroqService.shared.transcribeWithSegments(audioURL: audio, language: apiLang)
                await setResult(result, hasSubtitles: false)
                await appendLog("✅ Groq transcription complete (\(result.segments.count) segments)")
            } catch {
                await showError("Groq transcription failed: \(error.localizedDescription)")
            }
        } else {
            await appendLog("No subtitles available. Enable 'Groq fallback' to transcribe audio.")
            await showError("No subtitles available for language '\(targetLang)'. Enable Groq fallback.")
        }
    }

    // MARK: - SRT Parser (for yt-dlp subtitles → TranscriptionResult)

    private func parseSRT(_ srt: String) -> TranscriptionResult {
        var segments: [TranscriptionResult.Segment] = []
        var fullTexts: [String] = []

        let blocks = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            // Parse segment index
            guard let _ = Int(lines[0].trimmingCharacters(in: .whitespaces)) else { continue }

            // Parse timestamp line: 00:00:01,000 --> 00:00:04,000
            let timeLine = lines[1]
            let parts = timeLine.components(separatedBy: " --> ")
            guard parts.count == 2 else { continue }

            let start = parseSRTTime(parts[0])
            let end = parseSRTTime(parts[1])

            let text = lines[2...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")

            segments.append(TranscriptionResult.Segment(
                id: segments.count,
                start: start,
                end: end,
                text: text
            ))
            fullTexts.append(text)
        }

        return TranscriptionResult(
            text: fullTexts.joined(separator: " ").trimmingCharacters(in: .whitespaces),
            segments: segments
        )
    }

    private func parseSRTTime(_ time: String) -> Double {
        // Handle both comma and dot decimal separators: 00:01:23,456 or 00:01:23.456
        let normalized = time.replacingOccurrences(of: ",", with: ".")
        let components = normalized.components(separatedBy: ":")
        guard components.count == 3 else { return 0 }

        let h = Double(components[0]) ?? 0
        let m = Double(components[1]) ?? 0
        let s = Double(components[2]) ?? 0

        return h * 3600 + m * 60 + s
    }

    // MARK: - yt-dlp Helpers

    private struct VideoInfo {
        let title: String
        let duration: String
        let availableSubs: [String]
    }

    private func runYTLDProbe(_ url: String, _ tmpDir: URL) async throws -> VideoInfo {
        let titleOut = try await shell("/opt/homebrew/bin/yt-dlp", [
            "--print", "title",
            "--no-warnings",
            url
        ])
        let title = titleOut.trimmingCharacters(in: .whitespacesAndNewlines)

        let durationOut = try await shell("/opt/homebrew/bin/yt-dlp", [
            "--print", "duration_string",
            "--no-warnings",
            url
        ])
        let duration = durationOut.trimmingCharacters(in: .whitespacesAndNewlines)

        let subsOut = try? await shell("/opt/homebrew/bin/yt-dlp", [
            "--print", "subtitles",
            "--no-warnings",
            url
        ])
        var availableSubs: [String] = []
        if let subs = subsOut?.trimmingCharacters(in: .whitespacesAndNewlines), !subs.isEmpty, subs != "none" {
            availableSubs = subs.components(separatedBy: "\n").filter { !$0.isEmpty }
        }

        return VideoInfo(title: title, duration: duration, availableSubs: availableSubs)
    }

    private func runYTDLSRT(_ url: String, _ tmpDir: URL, lang: String) async throws -> String? {
        let output = tmpDir.appendingPathComponent("subs").path

        let exitCode = try await shellExitCode("/opt/homebrew/bin/yt-dlp", [
            "--skip-download",
            "--write-auto-sub",
            "--sub-lang", lang,
            "--sub-format", "srt",
            "--convert-subs", "srt",
            "-o", output,
            "--no-warnings",
            url
        ])

        if exitCode != 0 { return nil }

        let files = (try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)) ?? []
        let srtFile = files.first { $0.pathExtension == "srt" }
        guard let file = srtFile else { return nil }

        let content = try String(contentsOf: file, encoding: .utf8)
        return content
    }

    private func downloadAudio(_ url: String, _ tmpDir: URL) async throws -> URL {
        let output = tmpDir.appendingPathComponent("audio").path

        try await shell("/opt/homebrew/bin/yt-dlp", [
            "-x", "--audio-format", "m4a",
            "-o", "\(output).%(ext)s",
            "--no-warnings",
            url
        ])

        let files = (try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)) ?? []
        let audioFile = files.first { $0.pathExtension == "m4a" }
        guard let file = audioFile else {
            throw NSError(domain: "youtube", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio file found"])
        }
        return file
    }

    // MARK: - Shell Helpers

    @discardableResult
    private func shell(_ path: String, _ args: [String]) async throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        try task.run()
        task.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        if task.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw NSError(domain: "youtube", code: Int(task.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: err])
        }

        return String(data: outData, encoding: .utf8) ?? ""
    }

    @discardableResult
    private func shellExitCode(_ path: String, _ args: [String]) async throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    // MARK: - Formatting

    private func formattedContent(_ result: TranscriptionResult) -> String {
        switch outputFormat {
        case .text:  return result.text
        case .srt:   return result.srt
        case .segments: return groupedSegmentsText(result.segments)
        }
    }

    /// Merge segments into ~20-second groups, preferring sentence boundaries
    private func groupedSegments(_ segments: [TranscriptionResult.Segment]) -> [TranscriptionResult.Segment] {
        guard !segments.isEmpty else { return [] }

        var groups: [TranscriptionResult.Segment] = []
        var currentTexts: [String] = []
        var groupStart = segments[0].start
        var groupEnd = segments[0].end
        var groupId = 0

        for seg in segments {
            let duration = seg.end - groupStart

            if duration > 20.0 {
                // Check if current accumulated text ends with punctuation
                let currentText = currentTexts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                let endsOK = currentText.hasSuffix(".") || currentText.hasSuffix("!") || currentText.hasSuffix("?") || currentText.hasSuffix(",")

                if endsOK || duration > 30.0 {
                    // Flush group at punctuation boundary (or hard limit 30s)
                    groups.append(TranscriptionResult.Segment(
                        id: groupId,
                        start: groupStart,
                        end: groupEnd,
                        text: currentText
                    ))
                    groupId += 1
                    groupStart = seg.start
                    groupEnd = seg.end
                    currentTexts = [seg.text]
                } else {
                    // Keep going — look for a punctuation to break on
                    currentTexts.append(seg.text)
                    groupEnd = seg.end
                }
            } else {
                currentTexts.append(seg.text)
                groupEnd = seg.end
            }
        }

        // Flush last group
        if !currentTexts.isEmpty {
            groups.append(TranscriptionResult.Segment(
                id: groupId,
                start: groupStart,
                end: groupEnd,
                text: currentTexts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            ))
        }

        return groups
    }

    /// Formatted text for grouped segments
    private func groupedSegmentsText(_ segments: [TranscriptionResult.Segment]) -> String {
        groupedSegments(segments).map { seg in
            "[\(groupTimestamp(seg.start)) - \(groupTimestamp(seg.end))] \(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }.joined(separator: "\n\n")
    }

    private func groupTimestamp(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - UI State

    @MainActor
    private func appendLog(_ msg: String) {
        logLines.append(msg)
    }

    @MainActor
    private func setTitle(_ title: String) {
        videoTitle = title
    }

    @MainActor
    private func setStatus(_ msg: String) {
        statusMessage = msg
    }

    @MainActor
    private func setResult(_ result: TranscriptionResult, hasSubtitles: Bool) {
        transcriptionResult = result
        self.hasSubtitles = hasSubtitles
        statusMessage = nil
    }

    @MainActor
    private func showError(_ msg: String) {
        transcriptionResult = nil
        statusMessage = msg
    }

    private func saveSRT(_ content: String) {
        let title = videoTitle?.replacingOccurrences(of: "/", with: "-") ?? "transcript"
        let panel = NSSavePanel()
        panel.title = "Save SRT Subtitles"
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(title).srt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
