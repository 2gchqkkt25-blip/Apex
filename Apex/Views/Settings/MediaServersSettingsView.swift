//
//  MediaServersSettingsView.swift
//  Apex
//

import SwiftData
import SwiftUI

struct MediaServersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudSyncCoordinator.self) private var cloudSync: CloudSyncCoordinator?
    @Query(sort: \MediaServer.sortOrder) private var servers: [MediaServer]

    @AppStorage(MediaServerSelectionStore.key) private var selectedServerID: String = ""
    @State private var showingConnect: MediaServerKind?
    @State private var syncService = MediaServerSyncService.shared
    @State private var errorMessage: String?
    /// tvOS Settings drills in-place (no `NavigationLink`). iOS/macOS ignore this.
    var onEditServer: ((MediaServer) -> Void)? = nil

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            listBody
        #endif
    }

    #if os(tvOS)
        /// Flat rows inside the Settings detail `ScrollView` — a nested `List`
        /// fights the outer scroll (the pane jumps) and typically paints blank.
        private var tvBody: some View {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Media Servers")
                    Text("Connect Jellyfin, Emby, or Plex to browse your own movies and TV in the Media tab. This is separate from IPTV playlists.")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Connected")
                    if servers.isEmpty {
                        Text("No media servers yet. Add one below to start syncing your library.")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    } else {
                        ForEach(servers) { server in
                            HStack(spacing: 16) {
                                Button {
                                    selectedServerID = server.id.uuidString
                                } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: server.kind.systemImage)
                                            .font(.system(size: 22))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(server.name)
                                            Text(server.kind.displayName)
                                                .font(.system(size: 20))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if server.id.uuidString == selectedServerID {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(TVSettingsRowButtonStyle())

                                Button {
                                    onEditServer?(server)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(TVContentIconButtonStyle())
                                .accessibilityLabel("Edit \(server.name)")
                            }
                        }
                    }
                    Text("The checkmark marks the default server shown first in the Media tab.")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Add Server")
                    ForEach(MediaServerKind.allCases) { kind in
                        Button {
                            showingConnect = kind
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: kind.systemImage)
                                    .font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add \(kind.displayName)")
                                    Text(kind.connectHint)
                                        .font(.system(size: 20))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(TVSettingsRowButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fullScreenCover(item: $showingConnect) { kind in
                MediaConnectSheet(kind: kind) { server in
                    selectedServerID = server.id.uuidString
                    if MediaServerCatalogLimits.autoSyncLibraryOnConnect {
                        Task { await syncServer(server) }
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    #endif

    private var listBody: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Home media libraries", systemImage: "play.tv")
                        .font(.headline)
                    Text("Connect Jellyfin, Emby, or Plex to browse your own movies and TV in the **Media** tab. This is separate from IPTV playlists.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if servers.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Media Servers",
                        systemImage: "server.rack",
                        description: Text("Add a server below to start syncing your library.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(servers) { server in
                        NavigationLink {
                            MediaServerDetailSettingsView(server: server)
                        } label: {
                            MediaServerRow(server: server, isDefault: server.id.uuidString == selectedServerID)
                        }
                        #if !os(tvOS)
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteServer(server)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                } header: {
                    Text("Connected")
                } footer: {
                    Text("The default server is shown first in the Media tab when you have more than one.")
                }
            }

            Section {
                ForEach(MediaServerKind.allCases) { kind in
                    Button {
                        showingConnect = kind
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add \(kind.displayName)")
                                Text(kind.connectHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: kind.systemImage)
                        }
                    }
                }
            } header: {
                Text("Add Server")
            }
        }
        .navigationTitle("Media Servers")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $showingConnect) { kind in
            MediaConnectSheet(kind: kind) { server in
                selectedServerID = server.id.uuidString
                if MediaServerCatalogLimits.autoSyncLibraryOnConnect {
                    Task { await syncServer(server) }
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func syncServer(_ server: MediaServer) async {
        do {
            try await syncService.sync(server: server, container: modelContext.container)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteServer(_ server: MediaServer) {
        let serverID = server.id
        if selectedServerID == server.id.uuidString {
            selectedServerID = ""
        }
        guard let cloudSync else {
            try? MediaServerSyncService.shared.deleteServer(server, container: modelContext.container)
            return
        }
        Task {
            do {
                try await cloudSync.deleteMediaServer(id: serverID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct MediaServerRow: View {
    let server: MediaServer
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: server.kind.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.body.weight(.medium))
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                Text(server.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(server.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let last = server.lastSyncDate {
                    Text("Last sync \(last, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct MediaServerDetailSettingsView: View {
    @Bindable var server: MediaServer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSyncCoordinator.self) private var cloudSync: CloudSyncCoordinator?
    @AppStorage(MediaServerSelectionStore.key) private var selectedServerID: String = ""
    @State private var syncService = MediaServerSyncService.shared
    @State private var errorMessage: String?
    @State private var manualPlexURL = ""
    @State private var showDeleteConfirmation = false
    /// tvOS: leave the in-pane drill (e.g. after delete). Unused on iOS/macOS.
    var onClose: (() -> Void)? = nil

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            formBody
        #endif
    }

    #if os(tvOS)
        private var tvBody: some View {
            VStack(alignment: .leading, spacing: 32) {
                Text(server.name)
                    .font(.system(size: 34, weight: .bold))
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel(kindSectionTitle)
                    Text(server.kind.settingsBlurb)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    Text(server.baseURL)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Sync")
                    Button {
                        selectedServerID = server.id.uuidString
                    } label: {
                        HStack(spacing: 16) {
                            Text("Set as Default")
                            Spacer(minLength: 0)
                            if selectedServerID == server.id.uuidString {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                    .disabled(selectedServerID == server.id.uuidString)

                    Button {
                        Task { await syncNow() }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 22, weight: .medium))
                            Text(syncService.isSyncing && syncService.syncingServerID == server.id
                                ? (syncService.progressDetail.isEmpty ? "Syncing…" : syncService.progressDetail)
                                : "Sync Now")
                            Spacer(minLength: 0)
                            if let last = server.lastSyncDate {
                                Text(last, style: .relative)
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                    .disabled(syncService.isSyncing)
                }

                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 16) {
                        Text("Delete Server")
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(TVSettingsRowButtonStyle(isDestructive: true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert("Delete Server", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteServer() }
            } message: {
                Text("All synced movies and shows from this server will be removed from this device.")
            }
            .alert("Sync Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    #endif

    private var formBody: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(server.kind.displayName, systemImage: server.kind.systemImage)
                        .font(.headline)
                    Text(server.kind.settingsBlurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Display name") {
                TextField("Name", text: $server.name)
            }

            if server.kind == .plex {
                Section {
                    TextField("http://192.168.1.100:32400", text: $manualPlexURL)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        #endif
                    if !manualPlexURL.isEmpty {
                        Button("Use this address") {
                            server.baseURL = manualPlexURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } header: {
                    Text("Server address")
                } footer: {
                    Text("Current: \(server.baseURL)\n\nIf sync times out, enter your server's local IP from Plex → Settings → Network, then tap Sync Now.")
                }
            } else {
                Section("Server address") {
                    TextField("URL", text: $server.baseURL)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                }

                Section("Account") {
                    TextField("Username", text: $server.username)
                    SecureField("Password", text: $server.password)
                }
            }

            Section("Sync") {
                Button("Set as Default") {
                    selectedServerID = server.id.uuidString
                }
                .disabled(selectedServerID == server.id.uuidString)

                Button {
                    Task { await syncNow() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncService.isSyncing)

                if let last = server.lastSyncDate {
                    LabeledContent("Last sync") {
                        Text(last, style: .relative)
                    }
                } else {
                    LabeledContent("Last sync", value: "Never")
                }

                if syncService.isSyncing, syncService.syncingServerID == server.id {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(syncService.progressDetail.isEmpty ? "Syncing library…" : syncService.progressDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Delete Server", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(server.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            manualPlexURL = server.baseURL.contains(".plex.direct") ? "" : server.baseURL
        }
        .onDisappear {
            try? modelContext.save()
            cloudSync?.reconcile(reason: .queued)
        }
        .alert("Delete Server", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteServer()
            }
        } message: {
            Text("All synced movies and shows from this server will be removed from this device.")
        }
        .alert("Sync Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func syncNow() async {
        if server.kind == .plex, !manualPlexURL.trimmingCharacters(in: .whitespaces).isEmpty {
            server.baseURL = manualPlexURL.trimmingCharacters(in: .whitespaces)
        }
        do {
            try await syncService.sync(server: server, container: modelContext.container)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteServer() {
        let serverID = server.id
        if selectedServerID == server.id.uuidString {
            selectedServerID = ""
        }
        guard let cloudSync else {
            try? MediaServerSyncService.shared.deleteServer(server, container: modelContext.container)
            leaveDetail()
            return
        }
        Task {
            do {
                try await cloudSync.deleteMediaServer(id: serverID)
                leaveDetail()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func leaveDetail() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    #if os(tvOS)
        private var kindSectionTitle: LocalizedStringKey {
            switch server.kind {
            case .jellyfin: "Jellyfin"
            case .emby: "Emby"
            case .plex: "Plex"
            }
        }
    #endif
}

private extension MediaServerKind {
    var connectHint: String {
        switch self {
        case .jellyfin: "URL + username & password"
        case .emby: "URL + username & password"
        case .plex: "Plex.tv sign-in code"
        }
    }

    var settingsBlurb: String {
        switch self {
        case .jellyfin: "Libraries sync into the Media tab only — not your IPTV playlists."
        case .emby: "Libraries sync into the Media tab only — not your IPTV playlists."
        case .plex: "Sign in with Plex — Apex finds your server on the local network automatically."
        }
    }
}
