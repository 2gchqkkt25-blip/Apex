//
//  EPGSettingsView.swift
//  Apex
//
//  Manages standalone EPG (TV guide) sources: add/remove custom XMLTV feeds,
//  set how often the guide refreshes, and trigger a manual refresh. Sources
//  created automatically for a playlist are listed here too — they can be
//  enabled/disabled but not edited or deleted (they're managed by the playlist).
//

import SwiftData
import SwiftUI

struct EPGSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EPGSource.addedAt) private var sources: [EPGSource]
    @State private var epgSync = EPGSyncService.shared
    @AppStorage(SyncFrequency.epgStorageKey) private var freqRaw = SyncFrequency.epgDefaultValue.rawValue
    @AppStorage(LiveTVLayoutMode.storageKey) private var defaultViewRaw = LiveTVLayoutMode.list.rawValue

    @State private var showingAdd = false
    #if os(tvOS)
        @State private var addName = ""
        @State private var addURL = ""
    #endif

    private var frequency: Binding<SyncFrequency> {
        Binding(
            get: { SyncFrequency.resolveEPG(freqRaw) },
            set: { freqRaw = $0.rawValue }
        )
    }

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            formBody
        #endif
    }

    // MARK: - Actions

    private func addSource(name: String, url: String) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = EPGSource(
            name: trimmedName.isEmpty ? String(localized: "Custom Guide") : trimmedName,
            url: trimmedURL
        )
        modelContext.insert(source)
        try? modelContext.save()
    }

    private func delete(_ source: EPGSource) {
        modelContext.delete(source)
        try? modelContext.save()
    }
}

// MARK: - iOS / macOS

#if !os(tvOS)

    private extension EPGSettingsView {
        var formBody: some View {
            Form {
                defaultViewSection
                sourcesSection
                refreshSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("TV Guide")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .sheet(isPresented: $showingAdd) {
                    AddEPGSourceView { name, url in addSource(name: name, url: url) }
                }
        }

        var defaultViewSection: some View {
            Section {
                Picker("Default View", selection: Binding(
                    get: { LiveTVLayoutMode(rawValue: defaultViewRaw) ?? .list },
                    set: { defaultViewRaw = $0.rawValue }
                )) {
                    ForEach(LiveTVLayoutMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Live TV")
            } footer: {
                Text("Choose whether Live TV opens in the channel list or the programme guide by default.")
            }
        }

        var sourcesSection: some View {
            Section {
                if sources.isEmpty {
                    Text("No EPG sources yet. Adding a playlist sets one up automatically, or add a custom XMLTV feed below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources) { source in
                        EPGSourceRow(source: source)
                            .swipeActions(edge: .trailing) {
                                if source.isManual {
                                    Button("Delete", role: .destructive) { delete(source) }
                                }
                            }
                    }
                }

                Button {
                    showingAdd = true
                } label: {
                    Label("Add EPG Source", systemImage: "plus")
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Guide data is matched to channels across all your playlists.")
            }
        }

        var refreshSection: some View {
            Section {
                Picker("Refresh", selection: frequency) {
                    ForEach(SyncFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    epgSync.syncNow()
                } label: {
                    HStack {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        if epgSync.isSyncing {
                            Spacer()
                            if let progress = epgSync.syncProgress {
                                Text(progress, format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(epgSync.isSyncing || sources.isEmpty)

                if epgSync.isSyncing, let progress = epgSync.syncProgress {
                    ProgressView(value: progress)
                        .tint(ThemeManager.shared.colors.accent)
                }
            } header: {
                Text("Automatic Refresh")
            } footer: {
                if epgSync.isSyncing {
                    if let label = epgSync.syncProgressLabel {
                        Text("Downloading programme data — \(label). This can take a few minutes on large playlists — keep the app open.")
                    } else {
                        Text("Downloading programme data for your channels. This can take a few minutes on large playlists — keep the app open.")
                    }
                } else {
                    Text("Sync Now loads programme data for all live channels (same idea as Lume, using the provider API). The guide also fills in as you browse.")
                }
            }
        }
    }

    private struct EPGSourceRow: View {
        @Bindable var source: EPGSource

        var body: some View {
            Toggle(isOn: $source.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }

        private var subtitle: String {
            if source.syncStatus == .syncing {
                return String(localized: "Refreshing…")
            }
            if source.syncStatus == .error {
                if source.lastSyncDate != nil {
                    return String(localized: "Last refresh failed — showing previous guide if available")
                }
                return String(localized: "Last refresh failed")
            }
            if let last = source.lastSyncDate {
                return last.formatted(.relative(presentation: .named))
            }
            return source.isManual ? source.url : String(localized: "From playlist")
        }
    }

    /// A small sheet to add a manual XMLTV source.
    private struct AddEPGSourceView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var name = ""
        @State private var url = ""
        let onAdd: (String, String) -> Void

        var body: some View {
            NavigationStack {
                Form {
                    Section("Source") {
                        TextField("Name", text: $name)
                        TextField("XMLTV URL", text: $url)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                    }
                }
                #if os(macOS)
                .formStyle(.grouped)
                .frame(minWidth: 420, minHeight: 220)
                #endif
                .navigationTitle("Add EPG Source")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                onAdd(name, url)
                                dismiss()
                            }
                            .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            }
        }
    }

#endif

// MARK: - tvOS

#if os(tvOS)

    private extension EPGSettingsView {
        /// Rendered inline inside the Settings detail pane (the enclosing pane
        /// supplies the ScrollView, background and width framing).
        var tvBody: some View {
            VStack(alignment: .leading, spacing: 36) {
                tvDefaultViewSection
                tvSourcesSection
                tvAddSection
                tvRefreshSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        var tvDefaultViewSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("Default View")

                VStack(spacing: 2) {
                    ForEach(LiveTVLayoutMode.allCases) { mode in
                        Button {
                            defaultViewRaw = mode.rawValue
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 22))
                                Text(mode.label)
                                Spacer(minLength: 0)
                                if (LiveTVLayoutMode(rawValue: defaultViewRaw) ?? .list) == mode {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 24, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(TVSettingsRowButtonStyle())
                    }
                }

                Text("Choose whether Live TV opens in the channel list or the programme guide.")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    .padding(.top, 6)
            }
        }

        var tvSourcesSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("EPG Sources")

                if sources.isEmpty {
                    Text("No EPG sources yet. Adding a playlist sets one up automatically.")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 2) {
                        ForEach(sources) { source in
                            tvSourceRow(source)
                        }
                    }
                }
            }
        }

        func tvSourceRow(_ source: EPGSource) -> some View {
            HStack(spacing: 16) {
                Button {
                    source.isEnabled.toggle()
                    try? modelContext.save()
                } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text(tvSubtitle(source))
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Text(source.isEnabled ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(TVSettingsRowButtonStyle())

                if source.isManual {
                    Button {
                        delete(source)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(TVContentIconButtonStyle())
                    .accessibilityLabel("Delete \(source.name)")
                }
            }
        }

        func tvSubtitle(_ source: EPGSource) -> String {
            if source.syncStatus == .syncing {
                return String(localized: "Refreshing…")
            }
            if source.syncStatus == .error {
                return String(localized: "Last refresh failed")
            }
            if let last = source.lastSyncDate {
                return last.formatted(.relative(presentation: .named))
            }
            return source.isManual ? source.url : String(localized: "From playlist")
        }

        var tvAddSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("Add Custom Source")

                if showingAdd {
                    VStack(spacing: 18) {
                        TVSettingsField(title: "Name", placeholder: "Name", text: $addName, contentType: .name)
                        TVSettingsField(title: "XMLTV URL", placeholder: "XMLTV URL", text: $addURL, contentType: .URL)
                    }
                    VStack(spacing: 2) {
                        Button("Add Source") {
                            addSource(name: addName, url: addURL)
                            addName = ""
                            addURL = ""
                            showingAdd = false
                        }
                        .buttonStyle(TVSettingsRowButtonStyle())
                        .disabled(addURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Cancel") { showingAdd = false }
                            .buttonStyle(TVSettingsRowButtonStyle())
                    }
                } else {
                    Button {
                        showingAdd = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .medium))
                            Text("Add EPG Source")
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                }
            }
        }

        var tvRefreshFooterText: String {
            if epgSync.isSyncing, let label = epgSync.syncProgressLabel {
                return String(localized: "Downloading programme data — \(label).")
            }
            return String(localized: "The TV guide refreshes automatically in the background at this interval.")
        }

        var tvRefreshSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("Automatic Refresh")

                VStack(spacing: 2) {
                    ForEach(SyncFrequency.allCases) { option in
                        Button {
                            frequency.wrappedValue = option
                        } label: {
                            HStack(spacing: 16) {
                                Text(option.label)
                                Spacer(minLength: 0)
                                if frequency.wrappedValue == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 24, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(TVSettingsRowButtonStyle())
                    }

                    Button {
                        epgSync.syncNow()
                    } label: {
                        HStack(spacing: 16) {
                            Text("Sync Now")
                            Spacer(minLength: 0)
                            if epgSync.isSyncing {
                                if let progress = epgSync.syncProgress {
                                    Text(progress, format: .percent.precision(.fractionLength(0)))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                    .disabled(epgSync.isSyncing || sources.isEmpty)
                }

                if epgSync.isSyncing, let progress = epgSync.syncProgress {
                    ProgressView(value: progress)
                        .tint(ThemeManager.shared.colors.accent)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                }

                Text(tvRefreshFooterText)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    .padding(.top, 6)
            }
        }
    }

#endif
