import Foundation
import AppKit

// MARK: - Transcription Result with Segments
struct TranscriptionResult {
    var text: String
    var segments: [Segment]

    struct Segment {
        var id: Int
        var start: Double
        var end: Double
        var text: String
    }

    var srt: String {
        segments.map { seg in
            "\(seg.id + 1)\n\(formatSRTTime(seg.start)) --> \(formatSRTTime(seg.end))\n\(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }.joined(separator: "\n\n")
    }

    var segmentedText: String {
        segments.map { seg in
            "[\(formatShortTime(seg.start)) - \(formatShortTime(seg.end))] \(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }.joined(separator: "\n\n")
    }

    private func formatSRTTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private func formatShortTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
    }

    /// Merge another result after this one (chained chunks).
    mutating func append(_ other: TranscriptionResult, timeOffset: Double) {
        let nextId = segments.count
        for (i, seg) in other.segments.enumerated() {
            segments.append(Segment(
                id: nextId + i,
                start: seg.start + timeOffset,
                end: seg.end + timeOffset,
                text: seg.text
            ))
        }
        if !text.isEmpty && !other.text.isEmpty {
            // Keep full text as concatenation
        }
        // text is rebuilt by the caller
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case text; case srt; case segments
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: return "Plain Text"
        case .srt: return "SRT Subtitles"
        case .segments: return "Segments (timed)"
        }
    }
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .srt: return "captions.bubble"
        case .segments: return "text.badge.plus"
        }
    }
}

// MARK: - Groq API Service
final class GroqService {
    static let shared = GroqService()

    private let session: URLSession
    private let decoder = JSONDecoder()

    // Max chunk size: 20MB (Groq has 25MB limit, keep safe)
    private let maxFileSize: UInt64 = 20_000_000
    // Max chunk duration in seconds
    private let chunkDuration: Double = 120

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func transcribeWithSegments(audioURL: URL, language: String? = nil) async throws -> TranscriptionResult {
        let apiKey = apiKey()
        guard !apiKey.isEmpty else { throw GroqError.noApiKey }

        // Check if we need to split
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? UInt64) ?? 0
        let needsSplit = fileSize > maxFileSize

        if needsSplit {
            return try await transcribeChunked(audioURL: audioURL, language: language)
        } else {
            return try await transcribeSingle(audioURL: audioURL, language: language)
        }
    }

    func transcribe(audioURL: URL, language: String? = nil) async throws -> String {
        try await transcribeWithSegments(audioURL: audioURL, language: language).text
    }

    // MARK: - Single File Transcription

    private func transcribeSingle(audioURL: URL, language: String? = nil) async throws -> TranscriptionResult {
        let (body, boundary) = try buildRequest(audioURL: audioURL, language: language)
        let data = try await performRequest(body: body, boundary: boundary)
        return try decodeResponse(data)
    }

    // MARK: - Chunked Transcription with ffmpeg

    private func transcribeChunked(audioURL: URL, language: String? = nil) async throws -> TranscriptionResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Convert to WAV for easier splitting
        let wavURL = tempDir.appendingPathComponent("audio.wav")
        var args: [String] = ["-y", "-i", audioURL.path, "-ar", "16000", "-ac", "1", "-sample_fmt", "s16", wavURL.path]
        let convertResult = shell("/opt/homebrew/bin/ffmpeg", args)
        guard convertResult == 0 else {
            throw GroqError.networkError("ffmpeg conversion failed (exit \(convertResult))")
        }

        // Get duration
        let duration = try await getAudioDuration(wavURL)

        // Split into chunks
        let chunkPattern = tempDir.appendingPathComponent("chunk_%03d.m4a").path
        let splitArgs = [
            "-y", "-i", wavURL.path,
            "-f", "segment", "-segment_time", "\(Int(chunkDuration))",
            "-c:a", "aac", "-ar", "16000", "-ac", "1", "-b:a", "32k",
            chunkPattern
        ]
        let splitResult = shell("/opt/homebrew/bin/ffmpeg", splitArgs)
        guard splitResult == 0 else {
            throw GroqError.networkError("ffmpeg split failed (exit \(splitResult))")
        }

        // Find all chunks
        let fileManager = FileManager.default
        let chunks = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("chunk_") && $0.lastPathComponent.hasSuffix(".m4a") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !chunks.isEmpty else {
            throw GroqError.networkError("No chunks created by ffmpeg")
        }

        // Transcribe each chunk sequentially
        var allSegments: [TranscriptionResult.Segment] = []
        var allTexts: [String] = []

        for (index, chunkURL) in chunks.enumerated() {
            let timeOffset = Double(index) * chunkDuration

            let chunkResult = try await transcribeSingle(audioURL: chunkURL, language: language)

            for var seg in chunkResult.segments {
                seg.id = allSegments.count
                seg.start += timeOffset
                seg.end += timeOffset
                allSegments.append(seg)
            }
            allTexts.append(chunkResult.text)
        }

        return TranscriptionResult(
            text: allTexts.joined(separator: " ").trimmingCharacters(in: .whitespaces),
            segments: allSegments
        )
    }

    // MARK: - Request Building

    private func buildRequest(audioURL: URL, language: String? = nil) throws -> (body: Data, boundary: String) {
        let model = UserDefaults.standard.string(forKey: SettingsKeys.modelName) ?? "whisper-large-v3-turbo"
        let boundary = UUID().uuidString
        var body = Data()

        body += "--\(boundary)\r\n".data
        body += "Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data
        body += "Content-Type: audio/mp4\r\n\r\n".data
        body += try Data(contentsOf: audioURL)
        body += "\r\n".data

        body += "--\(boundary)\r\n".data
        body += "Content-Disposition: form-data; name=\"model\"\r\n\r\n".data
        body += "\(model)\r\n".data

        if let lang = language, !lang.isEmpty, lang != "auto" {
            body += "--\(boundary)\r\n".data
            body += "Content-Disposition: form-data; name=\"language\"\r\n\r\n".data
            body += "\(lang)\r\n".data
        }

        body += "--\(boundary)\r\n".data
        body += "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data
        body += "verbose_json\r\n".data

        body += "--\(boundary)--\r\n".data
        return (body, boundary)
    }

    private func performRequest(body: Data, boundary: String) async throws -> Data {
        let apiKey = apiKey()
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GroqError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GroqError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        return data
    }

    private func decodeResponse(_ data: Data) throws -> TranscriptionResult {
        struct RawSegment: Codable {
            var id: Int; let start: Double; let end: Double; let text: String
        }
        struct GroqVerboseResponse: Codable {
            var text: String; let segments: [RawSegment]?
        }

        do {
            let result = try decoder.decode(GroqVerboseResponse.self, from: data)
            let segments = result.segments?.map { raw in
                TranscriptionResult.Segment(id: raw.id, start: raw.start, end: raw.end, text: raw.text)
            } ?? []
            return TranscriptionResult(
                text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                segments: segments
            )
        } catch {
            throw GroqError.decodingError
        }
    }

    // MARK: - Helpers

    private func apiKey() -> String {
        UserDefaults.standard.string(forKey: SettingsKeys.groqApiKey) ?? ""
    }


    private func getAudioDuration(_ url: URL) async throws -> Double {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        task.arguments = ["-v", "error", "-show_entries", "format=duration",
                          "-of", "default=noprint_wrappers=1:nokey=1", url.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        return Double(str) ?? 0
    }

    @discardableResult
    private func shell(_ path: String, _ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }

    static func validateAPIKey(_ key: String) async -> Bool {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Errors
enum GroqError: Error, LocalizedError {
    case noApiKey; case invalidResponse; case networkError(String)
    case apiError(statusCode: Int, message: String); case decodingError

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "Groq API key not set. Add it in Settings."
        case .invalidResponse: return "Invalid response from Groq API."
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let code, let msg): return "API Error (\(code)): \(msg)"
        case .decodingError: return "Failed to decode transcription response."
        }
    }
}

private extension String {
    var data: Data { Data(self.utf8) }
}
