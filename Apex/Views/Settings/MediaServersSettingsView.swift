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

    var body: some View {
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

    var body: some View {
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
            dismiss()
            return
        }
        Task {
            do {
                try await cloudSync.deleteMediaServer(id: serverID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
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
