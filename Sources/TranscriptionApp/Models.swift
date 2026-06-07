import Foundation

// MARK: - Transcription History Item
struct TranscriptionItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let language: String?
    let source: Source
    let timestamp: Date
    let duration: TimeInterval?
    let fileName: String?

    enum Source: String, Codable {
        case file
        case microphone
    }

    var formattedDuration: String {
        guard let d = duration else { return "—" }
        let m = Int(d) / 60
        let s = Int(d) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    var formattedTimestamp: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: timestamp)
    }

    var sourceIcon: String {
        switch source {
        case .file: return "🎤"
        case .microphone: return "🎙️"
        }
    }
}

// MARK: - History Store
class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published var items: [TranscriptionItem] = []

    private let saveKey = "transcription_history"
    private let maxItems = 200

    private init() {
        load()
    }

    func add(_ item: TranscriptionItem) {
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func delete(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        items = (try? JSONDecoder().decode([TranscriptionItem].self, from: data)) ?? []
    }
}

// MARK: - Language Support
struct LanguageOption: Identifiable, Hashable {
    let id: String // language code
    let name: String
    let flag: String

    static let all: [LanguageOption] = [
        LanguageOption(id: "auto", name: "Auto-detect", flag: "🌐"),
        LanguageOption(id: "el", name: "Greek (Ελληνικά)", flag: "🇬🇷"),
        LanguageOption(id: "en", name: "English", flag: "🇺🇸"),
        LanguageOption(id: "es", name: "Spanish (Español)", flag: "🇪🇸"),
        LanguageOption(id: "fr", name: "French (Français)", flag: "🇫🇷"),
        LanguageOption(id: "de", name: "German (Deutsch)", flag: "🇩🇪"),
        LanguageOption(id: "it", name: "Italian (Italiano)", flag: "🇮🇹"),
        LanguageOption(id: "pt", name: "Portuguese (Português)", flag: "🇵🇹"),
        LanguageOption(id: "ru", name: "Russian (Русский)", flag: "🇷🇺"),
        LanguageOption(id: "ja", name: "Japanese (日本語)", flag: "🇯🇵"),
        LanguageOption(id: "ko", name: "Korean (한국어)", flag: "🇰🇷"),
        LanguageOption(id: "zh", name: "Chinese (中文)", flag: "🇨🇳"),
        LanguageOption(id: "ar", name: "Arabic (العربية)", flag: "🇸🇦"),
        LanguageOption(id: "tr", name: "Turkish (Türkçe)", flag: "🇹🇷"),
    ]
}

// MARK: - UserDefaults Keys
enum SettingsKeys {
    static let groqApiKey = "groq_api_key"
    static let defaultLanguage = "default_language"
    static let modelName = "model_name"
    static let autoPunctuation = "auto_punctuation"

    // LLM Provider (OpenAI-compatible)
    static let llmBaseURL = "llm_base_url"
    static let llmModel = "llm_model"
    static let llmApiKey = "llm_api_key"
}
