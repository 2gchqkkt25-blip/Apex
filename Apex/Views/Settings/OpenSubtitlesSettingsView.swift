//
//  OpenSubtitlesSettingsView.swift
//  Apex
//
//  Settings UI for configuring OpenSubtitles.com integration.
//  Allows the user to enter their API key and choose a preferred language.
//

import SwiftUI

struct OpenSubtitlesSettingsView: View {
    @AppStorage(OpenSubtitlesSettings.enabledKey) private var isEnabled = false
    @AppStorage(OpenSubtitlesSettings.apiKeyKey) private var apiKey = ""
    @AppStorage(OpenSubtitlesSettings.languageKey) private var language = "en"

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            formBody
        #endif
    }

    #if !os(tvOS)
    private var formBody: some View {
        Form {
            Section {
                Toggle("Enable OpenSubtitles", isOn: $isEnabled)
            } header: {
                Text("Subtitles")
            } footer: {
                Text("When enabled, Apex will automatically search for subtitles when the stream doesn't have embedded subtitle tracks.")
            }

            if isEnabled {
                Section {
                    TextField("API Key", text: $apiKey)
                        .textContentType(.password)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    Picker("Language", selection: $language) {
                        ForEach(OpenSubtitlesSettings.languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    Text("Get a free API key at opensubtitles.com/consumers. Sign up for a free account, then create a new consumer (app) to get your API key.")
                }

                Section {
                    Button(action: testConnection) {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else if let result = testResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(result.contains("✓") ? .green : .red)
                            }
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Subtitles")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    #endif

    #if os(tvOS)
    private var tvBody: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSettingsSectionLabel("Subtitles")

            Button {
                isEnabled.toggle()
            } label: {
                HStack {
                    Text("OpenSubtitles")
                    Spacer()
                    Text(isEnabled ? "On" : "Off")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(TVSettingsRowButtonStyle())

            if isEnabled {
                TVSettingsField(title: "API Key", placeholder: "Enter your API key", text: $apiKey, isSecure: true, contentType: .password)

                VStack(spacing: 2) {
                    ForEach(OpenSubtitlesSettings.languages.prefix(10), id: \.code) { lang in
                        Button {
                            language = lang.code
                        } label: {
                            HStack {
                                Text(lang.name)
                                Spacer()
                                if language == lang.code {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(TVSettingsRowButtonStyle())
                    }
                }

                Text("Get a free API key at opensubtitles.com/consumers. Sign up, create a consumer app, and enter the API key above.")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let results = try await OpenSubtitlesClient.shared.searchSubtitles(imdbId: "tt0111161")
                await MainActor.run {
                    testResult = "✓ Connected (\(results.count) results)"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}
