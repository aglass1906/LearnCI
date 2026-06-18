import SwiftUI
import UIKit

struct ProfileAISettingsView: View {
    @Bindable var profile: UserProfile
    @State private var openAIKey: String = ""
    @State private var openAISaved: Bool = false
    @State private var googleKey: String = ""
    @State private var googleSaved: Bool = false
    @State private var pasteMessage: String?
    @AppStorage(VideoPromptModel.userDefaultsKey) private var videoPromptModel: String = VideoPromptModel.openAI.rawValue

    private enum APIKeyField {
        case openAI
        case google
    }

    var body: some View {
        Form {
            // MARK: OpenAI
            Section {
                apiKeyEditor(text: $openAIKey, placeholder: "sk-...")

                Button {
                    pasteKey(UIPasteboard.general.string, into: .openAI, saveImmediately: true)
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used for story text, audio, cover art, and comprehension quizzes. Pasting saves immediately. Stored on-device only.")
                    if let pasteMessage {
                        Text(pasteMessage)
                    }
                }
            }

            Section {
                Button(action: saveOpenAIKey) {
                    HStack {
                        Text(openAISaved ? "Key Saved" : "Save Key")
                        if openAISaved {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(cleanKey(openAIKey).isEmpty)

                Button("Clear Key", role: .destructive) {
                    OpenAIAPIKeyStorage.remove()
                    openAIKey = ""
                    openAISaved = false
                }
            }

            // MARK: Google / Veo
            Section {
                apiKeyEditor(text: $googleKey, placeholder: "AIza...")

                Button {
                    pasteKey(UIPasteboard.general.string, into: .google, saveImmediately: true)
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
            } header: {
                Text("Google API Key")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used for AI scene video generation (Veo 3). Charged at \(VideoStyle.ratePerSecond) — approx. \(VideoStyle.estimatedCostRange) per 8-second clip. Pasting saves immediately. Stored on-device only.")
                    if let pasteMessage {
                        Text(pasteMessage)
                    }
                }
            }

            Section {
                Button(action: saveGoogleKey) {
                    HStack {
                        Text(googleSaved ? "Key Saved" : "Save Key")
                        if googleSaved {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(cleanKey(googleKey).isEmpty)

                Button("Clear Key", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: VeoService.userDefaultsKey)
                    googleKey = ""
                    googleSaved = false
                }
            }

            // MARK: Prompt Writing AI
            Section {
                Picker("Prompt Writing AI", selection: $videoPromptModel) {
                    ForEach(VideoPromptModel.allCases) { model in
                        Label(model.rawValue, systemImage: model.icon)
                            .tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Prompt Writing AI")
            } footer: {
                Text("Chooses which AI writes the cinematic text description sent to Veo 3 for video generation. Gemini uses your Google key at no extra cost. OpenAI uses your OpenAI key.")
            }
        }
        .navigationTitle("AI Settings")
        .onAppear {
            if let existing = OpenAIAPIKeyStorage.apiKey {
                openAIKey = existing
                openAISaved = true
            }
            if let existing = UserDefaults.standard.string(forKey: VeoService.userDefaultsKey) {
                googleKey = existing
                googleSaved = true
            }
        }
        .onChange(of: openAIKey) { _, _ in
            openAISaved = OpenAIAPIKeyStorage.apiKey == cleanKey(openAIKey)
        }
        .onChange(of: googleKey) { _, _ in
            googleSaved = UserDefaults.standard.string(forKey: VeoService.userDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) == cleanKey(googleKey)
        }
    }

    private func apiKeyEditor(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }

            TextEditor(text: text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .textSelection(.enabled)
        }
    }

    private func saveOpenAIKey() {
        let cleaned = cleanKey(openAIKey)
        guard !cleaned.isEmpty else { return }
        OpenAIAPIKeyStorage.save(cleaned)
        openAIKey = cleaned
        openAISaved = true
    }

    private func saveGoogleKey() {
        let cleaned = cleanKey(googleKey)
        guard !cleaned.isEmpty else { return }
        UserDefaults.standard.set(cleaned, forKey: VeoService.userDefaultsKey)
        googleKey = cleaned
        googleSaved = true
    }

    private func pasteKey(_ value: String?, into field: APIKeyField, saveImmediately: Bool) {
        let pasted = extractKey(from: value, for: field)
        guard !pasted.isEmpty else {
            pasteMessage = "Clipboard is empty or does not contain text."
            return
        }

        switch field {
        case .openAI:
            openAIKey = pasted
            if saveImmediately {
                saveOpenAIKey()
            }
            pasteMessage = "OpenAI key pasted and saved."
        case .google:
            googleKey = pasted
            if saveImmediately {
                saveGoogleKey()
            }
            pasteMessage = "Google key pasted and saved."
        }
    }

    private func cleanKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractKey(from value: String?, for field: APIKeyField) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }

        let pattern: String
        switch field {
        case .openAI:
            pattern = #"sk-[A-Za-z0-9_-]+"#
        case .google:
            pattern = #"AIza[A-Za-z0-9_-]+"#
        }

        if let range = trimmed.range(of: pattern, options: .regularExpression) {
            return String(trimmed[range])
        }

        return trimmed
    }
}
