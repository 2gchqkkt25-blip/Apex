//
//  MediaConnectSheet.swift
//  Apex
//
//  Connect Jellyfin, Emby, or Plex from the Media tab or Settings.
//

import SwiftData
import SwiftUI

struct MediaConnectSheet: View {
    let kind: MediaServerKind
    let onConnected: (MediaServer) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var serverName = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    // Plex PIN + server pick
    @State private var plexPin: PlexPinResponse?
    @State private var plexPollTask: Task<Void, Never>?
    @State private var plexAuthToken: String?
    @State private var plexServers: [PlexResource] = []
    @State private var selectedPlexServerID: String?
    @State private var manualPlexURL = ""
    @State private var showAdvancedPlex = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MediaConnectMetrics.sectionSpacing) {
                    header

                    if kind == .plex {
                        plexContent
                    } else {
                        credentialContent
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                            .foregroundStyle(.red)
                            .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                    }

                    actionButtons
                }
                .mediaConnectContentWidth()
            }
            .mediaConnectScreenBackground()
            .navigationTitle("Connect \(kind.displayName)")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .onDisappear {
                plexPollTask?.cancel()
                MediaConnectGate.isActive = false
            }
            .onAppear {
                MediaConnectGate.isActive = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 480, idealHeight: 640)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect \(kind.displayName)")
                .font(.system(size: MediaConnectMetrics.titleFontSize, weight: .bold))
            Text(kind.connectBlurb)
                .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
    }

    private var credentialContent: some View {
        VStack(spacing: 22) {
            MediaConnectField(
                title: "Server URL",
                placeholder: "https://jellyfin.example.com",
                text: $serverURL,
                kind: .url
            )
            MediaConnectField(title: "Username", placeholder: "Username", text: $username, kind: .username)
            MediaConnectField(title: "Password", placeholder: "Password", text: $password, isSecure: true, kind: .password)
            MediaConnectField(
                title: "Name in Apex",
                placeholder: "My \(kind.displayName)",
                text: $serverName,
                kind: .name
            )
        }
    }

    private var plexContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            MediaConnectSectionLabel("Sign In")
            VStack(alignment: .leading, spacing: 16) {
                Text("Authorize Apex at plex.tv/link using the code below.")
                    .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MediaConnectMetrics.horizontalPadding)

                if let pin = plexPin {
                    Text(pin.code)
                        .font(.system(size: MediaConnectMetrics.pinFontSize, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(pinBackground, in: RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius))
                        .padding(.horizontal, MediaConnectMetrics.horizontalPadding)

                    if plexAuthToken == nil {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Waiting for authorization…")
                                .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                    } else {
                        Label("Signed in to Plex", systemImage: "checkmark.circle.fill")
                            .font(.system(size: MediaConnectMetrics.secondaryFontSize, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                    }
                } else {
                    Button {
                        Task { await startPlexPin() }
                    } label: {
                        Label("Get Sign-In Code", systemImage: "qrcode")
                    }
                    .buttonStyle(MediaConnectPrimaryButtonStyle())
                    .disabled(isConnecting)
                    .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                }
            }

            if plexAuthToken != nil {
                MediaConnectSectionLabel("Choose Server")
                if plexServers.isEmpty {
                    Text("No servers found on this account.")
                        .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                } else {
                    VStack(spacing: 12) {
                        ForEach(plexServers, id: \.clientIdentifier) { server in
                            Button {
                                selectedPlexServerID = server.clientIdentifier
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(server.name)
                                        if let hint = plexConnectionHint(for: server) {
                                            Text(hint)
                                                .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(server.connections.count == 1 ? "1 connection" : "\(server.connections.count) connections")
                                                .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 16)
                                    if selectedPlexServerID == server.clientIdentifier {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(MediaConnectRowButtonStyle())
                        }
                    }
                    .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                }

                MediaConnectSectionLabel("Optional")
                VStack(spacing: 16) {
                    Toggle("Enter server address manually", isOn: $showAdvancedPlex)
                        .font(.system(size: MediaConnectMetrics.rowFontSize))
                        .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                    if showAdvancedPlex {
                        MediaConnectField(
                            title: "Server Address",
                            placeholder: "http://192.168.1.100:32400",
                            text: $manualPlexURL,
                            kind: .url
                        )
                    }
                    MediaConnectField(title: "Name in Apex", placeholder: "My Plex", text: $serverName, kind: .name)
                }

                if isConnecting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Finding reachable server…")
                            .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                }
            }
        }
    }

    private var pinBackground: Color {
        #if os(tvOS)
        Color.white.opacity(0.06)
        #else
        Color(.tertiarySystemFill)
        #endif
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                plexPollTask?.cancel()
                dismiss()
            }
            .buttonStyle(MediaConnectSecondaryButtonStyle())

            if kind != .plex {
                Button {
                    Task { await connectCredentials() }
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(MediaConnectPrimaryButtonStyle())
                .disabled(isConnecting || serverURL.trimmingCharacters(in: .whitespaces).isEmpty)
            } else if plexAuthToken != nil {
                Button {
                    Task { await finishPlexConnection() }
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text("Finish")
                    }
                }
                .buttonStyle(MediaConnectPrimaryButtonStyle())
                .disabled(isConnecting || selectedPlexServerID == nil)
            }
        }
        .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
        .padding(.top, 8)
    }

    // MARK: - Actions

    @MainActor
    private func connectCredentials() async {
        guard let baseURL = MediaServerURL.normalize(serverURL) else {
            errorMessage = MediaServerError.invalidURL.localizedDescription
            return
        }
        isConnecting = true
        defer { isConnecting = false }

        let client = MediaServerClientFactory.client(for: kind)
        do {
            let auth = try await client.authenticate(baseURL: baseURL, username: username, password: password)
            let server = MediaServer(
                name: serverName.isEmpty ? (auth.serverName ?? kind.displayName) : serverName,
                baseURL: baseURL.absoluteString,
                kind: kind
            )
            server.username = username
            server.password = password
            server.accessToken = auth.accessToken
            server.userId = auth.userId
            server.sortOrder = (try? modelContext.fetchCount(FetchDescriptor<MediaServer>())) ?? 0
            modelContext.insert(server)
            try modelContext.save()
            onConnected(server)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func startPlexPin() async {
        isConnecting = true
        defer { isConnecting = false }
        let plex = PlexClient()
        do {
            let pin = try await plex.createPin()
            plexPin = pin
            plexPollTask?.cancel()
            plexPollTask = Task {
                await pollPlexPin(id: pin.id, client: plex)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func pollPlexPin(id: Int, client: PlexClient) async {
        for _ in 0 ..< 120 {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(2))
            guard let polled = try? await client.pollPin(id: id),
                  let token = polled.authToken, !token.isEmpty
            else { continue }

            plexAuthToken = token
            do {
                let resources = try await client.listResources(token: token)
                plexServers = client.listBrowsableServers(from: resources)
                selectedPlexServerID = plexServers.first?.clientIdentifier
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        errorMessage = MediaServerError.plexPinExpired.localizedDescription
    }

    @MainActor
    private func finishPlexConnection() async {
        guard let token = plexAuthToken else { return }
        isConnecting = true
        defer { isConnecting = false }

        let plex = PlexClient()
        let manual = manualPlexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = plexServers.filter {
            selectedPlexServerID == nil || $0.clientIdentifier == selectedPlexServerID
        }
        do {
            let resolved = try await plex.resolveReachableConnection(
                token: token,
                preferredIdentifier: selectedPlexServerID,
                manualURL: manual.isEmpty ? nil : manual,
                currentURL: nil,
                knownServers: known.isEmpty ? nil : known
            )
            let displayName = serverName.isEmpty ? resolved.name : serverName
            let server = MediaServer(
                name: displayName,
                baseURL: resolved.url.absoluteString,
                kind: .plex
            )
            server.plexToken = token
            server.userId = "plex"
            server.plexServerIdentifier = resolved.identifier
            server.sortOrder = (try? modelContext.fetchCount(FetchDescriptor<MediaServer>())) ?? 0
            modelContext.insert(server)
            try modelContext.save()
            onConnected(server)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Surfaces whether Plex advertised a routable LAN address vs relay-only.
    private func plexConnectionHint(for server: PlexResource) -> String? {
        let plex = PlexClient()
        guard let best = plex.bestServerConnection(from: [server]) else { return nil }
        if let host = best.url.host, !host.contains(".plex.direct") {
            return "Local: \(host)"
        }
        return "Will search your network on Finish"
    }
}
