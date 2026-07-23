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
        @State private var appearance = SubtitleAppearance.current

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

                Section {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(appearance.fontSize)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appearance.fontSize, in: 14 ... 48, step: 1)

                    ColorPicker("Text Color", selection: $appearance.textColor)

                    HStack {
                        Text("Background Opacity")
                        Spacer()
                        Text("\(Int(appearance.backgroundOpacity * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appearance.backgroundOpacity, in: 0 ... 1, step: 0.1)

                    HStack {
                        Text("Bottom Offset")
                        Spacer()
                        Text("\(Int(appearance.bottomOffset)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appearance.bottomOffset, in: 0 ... 120, step: 4)

                    Picker("Position", selection: $appearance.position) {
                        Text("Bottom").tag(SubtitlePosition.bottom)
                        Text("Center").tag(SubtitlePosition.center)
                    }

                    Button("Reset to Defaults") {
                        resetAppearance()
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Font size, color, background opacity, and position affect all subtitle rendering (embedded and external).")
                }

                #if os(macOS)
                    Section {
                        Text("Subtitle Preview")
                            .font(.system(size: appearance.fontSize, weight: .medium))
                            .foregroundStyle(appearance.textColor)
                            .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(.black.opacity(appearance.backgroundOpacity), in: RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity)
                    } header: {
                        Text("Preview")
                    }
                #endif
            }
            .navigationTitle("Subtitles")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .onChange(of: isEnabled) { OpenSubtitlesSettings.syncToCloud() }
                .onChange(of: wyzieApiKey) { OpenSubtitlesSettings.syncToCloud() }
                .onChange(of: language) { OpenSubtitlesSettings.syncToCloud() }
                .onChange(of: appearance.fontSize) { appearance.save() }
                .onChange(of: appearance.textColor) { appearance.save() }
                .onChange(of: appearance.backgroundOpacity) { appearance.save() }
                .onChange(of: appearance.bottomOffset) { appearance.save() }
                .onChange(of: appearance.position) { appearance.save() }
                .onAppear { OpenSubtitlesSettings.syncFromCloud() }
        }

        private func resetAppearance() {
            let defaults = AppearanceDefaults()
            appearance.fontSize = defaults.fontSize
            appearance.textColor = defaults.textColor
            appearance.backgroundOpacity = defaults.backgroundOpacity
            appearance.bottomOffset = defaults.bottomOffset
            appearance.position = defaults.position
            appearance.save()
        }

        private struct AppearanceDefaults {
            let fontSize: CGFloat = {
                #if os(tvOS)
                    28
                #else
                    17
                #endif
            }()

            let textColor: Color = .white
            let backgroundOpacity: Double = 0.6
            let bottomOffset: CGFloat = {
                #if os(tvOS)
                    60
                #else
                    40
                #endif
            }()

            let position: SubtitlePosition = .bottom
        }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
        @State private var appearance = SubtitleAppearance.current
        @State private var fontSize: Double = SubtitleAppearance.current.fontSize
        @State private var textColorHex: String = SubtitleAppearance.current.textColor.hexString
        @State private var backgroundOpacity: Double = SubtitleAppearance.current.backgroundOpacity
        @State private var bottomOffset: Double = SubtitleAppearance.current.bottomOffset
        @State private var position: SubtitlePosition = SubtitleAppearance.current.position

        private let fontSizes: [Double] = [14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40, 44, 48]
        private let opacityOptions: [Double] = [0, 0.2, 0.4, 0.6, 0.8, 1.0]
        private let offsetOptions: [Double] = [0, 20, 40, 60, 80, 100, 120]
        private let colorOptions: [(String, Color)] = [
            ("FFFFFF", .white),
            ("FFFF00", .yellow),
            ("00FF00", .green),
            ("00FFFF", .cyan),
            ("FFA500", .orange),
            ("FF69B4", .pink)
        ]

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

                // Appearance
                TVSettingsSectionLabel("Appearance")
                    .padding(.top, 8)

                Text("Font Size: \(Int(fontSize)) pt")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(fontSizes, id: \.self) { size in
                            Button {
                                fontSize = size
                                saveAppearance()
                            } label: {
                                Text("\(Int(size))")
                                    .frame(minWidth: 48)
                                    .padding(.vertical, 10)
                                    .background(fontSize == size ? Color.blue : Color.white.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                }

                Text("Text Color")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                HStack(spacing: 12) {
                    ForEach(colorOptions, id: \.0) { hex, color in
                        Button {
                            textColorHex = hex
                            saveAppearance()
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(textColorHex == hex ? Color.blue : Color.clear, lineWidth: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                Text("Background Opacity: \(Int(backgroundOpacity * 100))%")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                HStack(spacing: 12) {
                    ForEach(opacityOptions, id: \.self) { opacity in
                        Button {
                            backgroundOpacity = opacity
                            saveAppearance()
                        } label: {
                            Text("\(Int(opacity * 100))%")
                                .frame(minWidth: 48)
                                .padding(.vertical, 10)
                                .background(backgroundOpacity == opacity ? Color.blue : Color.white.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                Text("Bottom Offset: \(Int(bottomOffset)) pt")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                HStack(spacing: 12) {
                    ForEach(offsetOptions, id: \.self) { offset in
                        Button {
                            bottomOffset = offset
                            saveAppearance()
                        } label: {
                            Text("\(Int(offset))")
                                .frame(minWidth: 48)
                                .padding(.vertical, 10)
                                .background(bottomOffset == offset ? Color.blue : Color.white.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                Text("Position")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                HStack(spacing: 12) {
                    ForEach(SubtitlePosition.allCases, id: \.self) { pos in
                        Button {
                            position = pos
                            saveAppearance()
                        } label: {
                            Text(pos == .bottom ? "Bottom" : "Center")
                                .frame(minWidth: 100)
                                .padding(.vertical, 10)
                                .background(position == pos ? Color.blue : Color.white.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                Button("Reset to Defaults") {
                    let def = AppearanceDefaults()
                    fontSize = def.fontSize
                    textColorHex = def.textColor.hexString
                    backgroundOpacity = def.backgroundOpacity
                    bottomOffset = def.bottomOffset
                    position = def.position
                    saveAppearance()
                }
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: isEnabled) { OpenSubtitlesSettings.syncToCloud() }
            .onChange(of: wyzieApiKey) { OpenSubtitlesSettings.syncToCloud() }
            .onChange(of: language) { OpenSubtitlesSettings.syncToCloud() }
            .onAppear { OpenSubtitlesSettings.syncFromCloud() }
        }

        private func saveAppearance() {
            appearance.fontSize = fontSize
            appearance.textColor = Color(hex: textColorHex) ?? .white
            appearance.backgroundOpacity = backgroundOpacity
            appearance.bottomOffset = bottomOffset
            appearance.position = position
            appearance.save()
        }

        private struct AppearanceDefaults {
            let fontSize: CGFloat = {
                #if os(tvOS)
                    28
                #else
                    17
                #endif
            }()

            let textColor: Color = .white
            let backgroundOpacity: Double = 0.6
            let bottomOffset: CGFloat = {
                #if os(tvOS)
                    60
                #else
                    40
                #endif
            }()

            let position: SubtitlePosition = .bottom
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
