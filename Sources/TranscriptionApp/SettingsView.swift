import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage(SettingsKeys.groqApiKey) private var groqApiKey: String = ""
    @AppStorage(SettingsKeys.defaultLanguage) private var defaultLanguage: String = "auto"
    @AppStorage(SettingsKeys.modelName) private var modelName: String = "whisper-large-v3-turbo"

    @AppStorage(SettingsKeys.llmBaseURL) private var llmBaseURL: String = "https://api.groq.com/openai/v1"
    @AppStorage(SettingsKeys.llmModel) private var llmModel: String = "llama-3.3-70b-versatile"
    @AppStorage(SettingsKeys.llmApiKey) private var llmApiKey: String = ""

    @State private var isAPIKeyValid: Bool?
    @State private var isValidating = false
    @State private var showAPIKey = false

    @State private var isLLMValid: Bool?
    @State private var isLLMValidating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - API Key
                settingsSection("Groq API Key") {
                    SecureField("gsk_...", text: $groqApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: groqApiKey) { _, _ in
                            isAPIKeyValid = nil
                        }

                    HStack {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Validating...")
                                .foregroundColor(.secondary)
                        } else if let valid = isAPIKeyValid {
                            if valid {
                                Label("API key is valid", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Label("Invalid API key", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }

                        Spacer()

                        Button("Validate") {
                            validateKey()
                        }
                        .disabled(groqApiKey.isEmpty || isValidating)

                        if !groqApiKey.isEmpty {
                            Button(showAPIKey ? "Hide" : "Show") {
                                showAPIKey.toggle()
                            }
                        }
                    }

                    if showAPIKey && !groqApiKey.isEmpty {
                        Text(groqApiKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    Text("Get your API key from console.groq.com")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Language
                settingsSection("Default Language") {
                    Picker("Language", selection: $defaultLanguage) {
                        ForEach(LanguageOption.all) { lang in
                            HStack {
                                Text(lang.flag)
                                Text(lang.name)
                            }.tag(lang.id)
                        }
                    }
                    .labelsHidden()

                    Text("Used for both File and Mic transcription. Auto-detect works well for most cases.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Model
                settingsSection("Model") {
                    Picker("Model", selection: $modelName) {
                        Text("whisper-large-v3-turbo").tag("whisper-large-v3-turbo")
                        Text("whisper-large-v3").tag("whisper-large-v3")
                        Text("distil-whisper-large-v3-en").tag("distil-whisper-large-v3-en")
                    }
                    .labelsHidden()

                    Text("whisper-large-v3-turbo is recommended — fast and accurate")          .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - LLM Provider
                settingsSection("LLM Provider (Polish / Translate)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Used to polish transcription errors and translate text.")
                            .font(.caption).foregroundColor(.secondary)

                        HStack {
                            Text("Base URL:")
                                .frame(width: 70, alignment: .trailing)
                            TextField("https://api.groq.com/openai/v1", text: $llmBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        HStack {
                            Text("Model:")
                                .frame(width: 70, alignment: .trailing)
                            TextField("llama-3.3-70b-versatile", text: $llmModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        HStack {
                            Text("API Key:")
                                .frame(width: 70, alignment: .trailing)
                            SecureField("gsk_... or sk-...", text: $llmApiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        HStack {
                            if isLLMValidating {
                                ProgressView().scaleEffect(0.8)
                                Text("Validating...").foregroundColor(.secondary)
                            } else if let valid = isLLMValid {
                                Label(valid ? "Connected" : "Failed", systemImage: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(valid ? .green : .red)
                            }
                            Spacer()
                            Button("Test Connection") { validateLLM() }
                                .disabled(llmApiKey.isEmpty || isLLMValidating)
                        }
                    }
                }

                // MARK: - Hotkey Configuration
                settingsSection("Hotkey Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Double-tap Right Command")
                                .font(.system(.body, design: .monospaced))
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text("→ Toggle microphone recording")
                        }

                        Text("Works in any app. Requires Accessibility permission.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Label("Accessibility:", systemImage: "hand.raised.fill")
                                .foregroundColor(.secondary)
                            Circle()
                                .fill(AXIsProcessTrusted() ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(AXIsProcessTrusted() ? "Granted" : "Not Granted")
                                .foregroundColor(.secondary)

                            if !AXIsProcessTrusted() {
                                Button("Open Settings") {
                                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                                    NSWorkspace.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // MARK: - Permissions
                settingsSection("Privacy") {
                    Button("Open Microphone Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)

                    Button("Open Accessibility Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
                .padding(.leading, 4)
            Divider()
        }
    }

    // MARK: - Validation

    private func validateKey() {
        guard !groqApiKey.isEmpty else { return }
        isValidating = true
        isAPIKeyValid = nil

        Task {
            let valid = await GroqService.validateAPIKey(groqApiKey)
            await MainActor.run {
                isAPIKeyValid = valid
                isValidating = false
            }
        }
    }

    private func validateLLM() {
        guard !llmApiKey.isEmpty else { return }
        isLLMValidating = true
        isLLMValid = nil

        Task {
            let valid = await LLMService.validate(baseURL: llmBaseURL, model: llmModel, apiKey: llmApiKey)
            await MainActor.run {
                isLLMValid = valid
                isLLMValidating = false
            }
        }
    }
}
