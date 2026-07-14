//
//  OpenSubtitlesSettingsView.swift
//  Apex
//
//  Settings UI for configuring subtitles via Wyzie Subs.
//

import SwiftUI

struct OpenSubtitlesSettingsView: View {
    @AppStorage(SubtitleSettings.enabledKey) private var isEnabled = false
    @AppStorage(SubtitleSettings.wyzieApiKeyKey) private var wyzieApiKey = ""
    @AppStorage(SubtitleSettings.languageKey) private var language = "en"

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            formBody
        #endif
    }

    // MARK: - iOS / macOS

    #if !os(tvOS)
    private var formBody: some View {
        Form {
            Section {
                Toggle("Enable Subtitles", isOn: $isEnabled)
            } header: {
                Text("Subtitles")
            } footer: {
                Text("When enabled, Apex will automatically search for subtitles when the stream doesn't have embedded subtitle tracks.")
            }

            if isEnabled {
                Section {
                    TextField("API Key", text: $wyzieApiKey)
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
                    Text("Get a free API key at store.wyzie.io/redeem — just verify with your email. 1,000 requests per day at no cost.")
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
                    .disabled(wyzieApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Subtitles")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: isEnabled) { OpenSubtitlesSettings.syncToCloud() }
        .onChange(of: wyzieApiKey) { OpenSubtitlesSettings.syncToCloud() }
        .onChange(of: language) { OpenSubtitlesSettings.syncToCloud() }
        .onAppear { OpenSubtitlesSettings.syncFromCloud() }
    }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
    private var tvBody: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVSettingsSectionLabel("Subtitles")

            Button {
                isEnabled.toggle()
            } label: {
                HStack {
                    Text("Subtitles")
                    Spacer()
                    Text(isEnabled ? "On" : "Off")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(TVSettingsRowButtonStyle())

            if isEnabled {
                TVSettingsField(title: "API Key", placeholder: "Enter your API key", text: $wyzieApiKey, isSecure: true, contentType: .password)

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

                Text("Get a free key at store.wyzie.io/redeem — just verify with your email. 1,000 requests per day.")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isEnabled) { OpenSubtitlesSettings.syncToCloud() }
        .onChange(of: wyzieApiKey) { OpenSubtitlesSettings.syncToCloud() }
        .onChange(of: language) { OpenSubtitlesSettings.syncToCloud() }
        .onAppear { OpenSubtitlesSettings.syncFromCloud() }
    }
    #endif

    // MARK: - Test

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let url = try await WyzieSubsClient.shared.fetchBestSubtitle(imdbId: "tt0111161")
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    testResult = "✓ Connected"
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
