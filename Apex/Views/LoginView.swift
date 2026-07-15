import SwiftData
import SwiftUI
#if !os(tvOS)
    import UniformTypeIdentifiers
#endif

struct LoginView: View {
    /// Whether this view is presented modally (the Settings "Add Playlist"
    /// sheet / cover) and should therefore offer a Cancel button and dismiss
    /// itself once a playlist is added. False when it's the window's root
    /// content on first launch — there is nothing to cancel to, and on macOS
    /// calling `dismiss()` on root content closes the whole window (the app
    /// keeps running but loses its only window, forcing a relaunch from the
    /// Dock). Adding the playlist swaps the root to MainTabView on its own via
    /// ContentView's @Query, so no dismissal is needed there.
    ///
    /// This is passed explicitly rather than read from `@Environment(\.isPresented)`
    /// because on macOS that value is `true` even for non-presented root content.
    var isModal = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager

    @State private var sourceType: PlaylistSourceType = .xtream

    @State private var name = ""
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    // m3u fields
    @State private var m3uURL = ""
    @State private var epgURL = ""
    // Stremio field
    @State private var stremioURL = ""
    #if !os(tvOS)
        @State private var showFileImporter = false
    #endif

    // Stalker portal fields. The MAC defaults to a freshly generated MAG-style
    // address so a user without a provider-issued MAC still gets a valid one.
    @State private var portalURL = ""
    @State private var macAddress = StalkerMAC.generate()

    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isFormValid: Bool {
        switch sourceType {
        case .xtream:
            !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.isEmpty
        case .m3u:
            !m3uURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stalker:
            !portalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stremio:
            StremioURL.normalize(stremioURL) != nil
        }
    }

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            formBody
        #endif
    }

    #if !os(tvOS)
        private var formBody: some View {
            NavigationStack {
                Form {
                    Section {
                        Picker("Playlist Type", selection: $sourceType) {
                            Text("Xtream").tag(PlaylistSourceType.xtream)
                            Text("M3U").tag(PlaylistSourceType.m3u)
                            Text("Stalker").tag(PlaylistSourceType.stalker)
                            Text("Stremio").tag(PlaylistSourceType.stremio)
                        }
                        .pickerStyle(.segmented)
                        .tint(themeManager.colors.accent)
                    }

                    switch sourceType {
                    case .xtream: xtreamSection
                    case .m3u: m3uSection
                    case .stalker: stalkerSection
                    case .stremio: stremioSection
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }

                    Section {
                        Button(action: validateAndAddPlaylist) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Add Playlist")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isLoading)
                    }
                }
                #if os(macOS)
                .formStyle(.grouped)
                #endif
                .scrollContentBackground(.hidden)
                .background(themeManager.colors.background)
                .navigationTitle("Add Playlist")
                .toolbar {
                    // Only offer Cancel when presented modally (the Settings
                    // sheet). On first launch there is nothing to cancel to.
                    if isModal {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                                .disabled(isLoading)
                        }
                    }
                }
                .interactiveDismissDisabled(isLoading)
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: Self.playlistFileTypes
                ) { result in
                    handleFileImport(result)
                }
            }
        }

        private var xtreamSection: some View {
            Section {
                TextField("e.g. My IPTV", text: $name)
                    .textContentType(.name)

                TextField("e.g. http://example.com:8080", text: $serverURL)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                    .autocorrectionDisabled()
                    .textContentType(.URL)

                TextField("Username", text: $username)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()
                    .textContentType(.username)

                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Server Connection")
            } footer: {
                Text("Your credentials are stored locally on this device.")
            }
        }

        private var m3uSection: some View {
            Section {
                TextField("e.g. My IPTV", text: $name)
                    .textContentType(.name)

                TextField("e.g. http://example.com/playlist.m3u", text: $m3uURL)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                    .autocorrectionDisabled()
                    .textContentType(.URL)

                Button("Choose Local File…") { showFileImporter = true }

                TextField("EPG URL (optional)", text: $epgURL)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                    .autocorrectionDisabled()
                    .textContentType(.URL)
            } header: {
                Text("M3U Playlist")
            } footer: {
                Text("Enter the playlist URL or choose a local m3u/m3u8 file. The EPG URL is read from the playlist when left empty.")
            }
        }

        private var stalkerSection: some View {
            Section {
                TextField("e.g. My IPTV", text: $name)
                    .textContentType(.name)

                TextField("e.g. http://example.com:8080/c/", text: $portalURL)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                    .autocorrectionDisabled()
                    .textContentType(.URL)

                HStack {
                    TextField("MAC Address", text: $macAddress)
                    #if os(iOS)
                        .textInputAutocapitalization(.characters)
                    #endif
                        .autocorrectionDisabled()
                    Button {
                        macAddress = StalkerMAC.generate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Generate a new MAC address")
                }

                TextField("Username (optional)", text: $username)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()
                    .textContentType(.username)

                SecureField("Password (optional)", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Stalker Portal")
            } footer: {
                Text("Enter the portal URL and the MAC address your provider authorized. Most portals need only the portal URL and MAC.")
            }
        }

        private var stremioSection: some View {
            Section {
                TextField("e.g. My Addon", text: $name)
                    .textContentType(.name)

                TextField("e.g. https://example.com/", text: $stremioURL)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                    .autocorrectionDisabled()
                    .textContentType(.URL)
            } header: {
                Text("Stremio Addon")
            } footer: {
                Text("Enter the manifest URL of a Stremio addon. The addon's catalogs will be synced automatically.")
            }
        }
    #endif

    #if os(tvOS)
        private var stalkerHint: LocalizedStringKey {
            switch sourceType {
            case .xtream: "Your credentials are stored locally on this device."
            case .m3u: "The EPG URL is read from the playlist when left empty."
            case .stalker: "Enter the portal URL and the MAC address your provider authorized."
            case .stremio: "Enter the manifest URL of a Stremio addon."
            }
        }

        private var tvBody: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add Playlist")
                            .font(.system(size: 38, weight: .bold))
                        Text("Connect to your IPTV provider")
                            .font(.system(size: TVSettingsMetrics.secondaryFontSize))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                    Picker("Playlist Type", selection: $sourceType) {
                        Text("Xtream").tag(PlaylistSourceType.xtream)
                        Text("M3U").tag(PlaylistSourceType.m3u)
                        Text("Stalker").tag(PlaylistSourceType.stalker)
                        Text("Stremio").tag(PlaylistSourceType.stremio)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                    VStack(spacing: 22) {
                        TVSettingsField(title: "Name", placeholder: "e.g. My IPTV", text: $name, contentType: .name)
                        switch sourceType {
                        case .xtream:
                            TVSettingsField(title: "Server URL", placeholder: "e.g. http://example.com:8080", text: $serverURL, contentType: .URL)
                            TVSettingsField(title: "Username", placeholder: "Username", text: $username, contentType: .username)
                            TVSettingsField(title: "Password", placeholder: "Password", text: $password, isSecure: true, contentType: .password)
                        case .m3u:
                            TVSettingsField(title: "Playlist URL", placeholder: "e.g. http://example.com/playlist.m3u", text: $m3uURL, contentType: .URL)
                            TVSettingsField(title: "EPG URL (optional)", placeholder: "e.g. http://example.com/guide.xml", text: $epgURL, contentType: .URL)
                        case .stalker:
                            TVSettingsField(title: "Portal URL", placeholder: "e.g. http://example.com:8080/c/", text: $portalURL, contentType: .URL)
                            TVSettingsField(title: "MAC Address", placeholder: "00:1A:79:xx:xx:xx", text: $macAddress, contentType: nil)
                            TVSettingsField(title: "Username (optional)", placeholder: "Username", text: $username, contentType: .username)
                            TVSettingsField(title: "Password (optional)", placeholder: "Password", text: $password, isSecure: true, contentType: .password)
                        case .stremio:
                            TVSettingsField(title: "Manifest URL", placeholder: "e.g. https://example.com/", text: $stremioURL, contentType: .URL)
                        }
                    }

                    Text(stalkerHint)
                        .font(.system(size: TVSettingsMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                    Text("Press and hold Select on a field to copy or paste.")
                        .font(.system(size: TVSettingsMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: TVSettingsMetrics.secondaryFontSize))
                            .foregroundStyle(.red)
                            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    }

                    HStack(spacing: 16) {
                        Button(action: addPlaylist) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Label("Add Playlist", systemImage: "plus")
                            }
                        }
                        .buttonStyle(TVSettingsActionButtonStyle(prominent: true))
                        .disabled(!isFormValid || isLoading)

                        // Only offer Cancel when presented modally (the Settings
                        // cover); on first launch there is nothing to cancel to.
                        if isModal {
                            Button("Cancel") { dismiss() }
                                .buttonStyle(TVSettingsActionButtonStyle())
                                .disabled(isLoading)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                }
                .frame(maxWidth: TVSettingsMetrics.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 48)
                .padding(.vertical, 72)
            }
            .tvSettingsBackground()
        }
    #endif

    // MARK: - Add playlist

    /// Validates the form and either proceeds or shows inline feedback.  Called
    /// by the "Add Playlist" button, which stays enabled so its label never
    /// washes out against the background (the disabled-opacity contrast bug).
    private func validateAndAddPlaylist() {
        guard isFormValid else {
            switch sourceType {
            case .xtream:
                if serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "Enter your server URL to continue."
                } else if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "Enter your username to continue."
                } else {
                    errorMessage = "Enter your password to continue."
                }
            case .m3u:
                errorMessage = "Enter a playlist URL or choose a local file."
            case .stalker:
                errorMessage = "Enter the portal URL to continue."
            case .stremio:
                if stremioURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "Enter the manifest URL to continue."
                } else if StremioURL.normalize(stremioURL) == nil {
                    errorMessage = "Enter a valid manifest URL to continue."
                }
            }
            return
        }
        errorMessage = nil
        addPlaylist()
    }

    private func addPlaylist() {
        switch sourceType {
        case .xtream: loginXtream()
        case .m3u: addM3UPlaylist()
        case .stalker: addStalkerPlaylist()
        case .stremio: addStremioPlaylist()
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loginXtream() {
        isLoading = true
        errorMessage = nil

        let playlistName = trimmedName.isEmpty ? "My Playlist" : trimmedName

        Task {
            let playlist = Playlist(
                name: playlistName,
                serverURL: serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            let client = XtreamClient()
            do {
                try await withConnectionTimeout {
                    let info = try await client.getInfo(playlist: playlist)
                    playlist.serverTimezone = info.serverInfo.timezone
                    playlist.userStatus = info.userInfo.status
                    playlist.maxConnections = String(info.userInfo.maxConnections ?? "0")
                    playlist.activeConnections = String(info.userInfo.activeCons ?? "0")
                    playlist.expDate = info.userInfo.expDate
                    insertAndFinish(playlist)
                }
            } catch {
                errorMessage = Self.verboseError(error, context: "Xtream login to \(serverURL)")
                isLoading = false
            }
        }
    }

    private func addM3UPlaylist() {
        isLoading = true
        errorMessage = nil

        let playlistName = trimmedName.isEmpty ? "My Playlist" : trimmedName
        let urlString = m3uURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let epgURLString = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await withConnectionTimeout {
                    // Cheap validation: stream just the head of the file and check
                    // for m3u markers, so adding a huge playlist stays instant —
                    // the full download happens during the first sync.
                    try await M3UClient().validatePlaylist(at: urlString)
                    let playlist = Playlist(name: playlistName, m3uURL: urlString, epgURL: epgURLString)
                    insertAndFinish(playlist)
                }
            } catch {
                errorMessage = Self.verboseError(error, context: "M3U validation of \(urlString)")
                isLoading = false
            }
        }
    }

    private func addStalkerPlaylist() {
        isLoading = true
        errorMessage = nil

        let playlistName = trimmedName.isEmpty ? "My Playlist" : trimmedName
        let portal = portalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let mac = macAddress.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        Task {
            let playlist = Playlist(
                name: playlistName,
                portalURL: portal,
                macAddress: mac,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            let client = StalkerClient(configuration: StalkerClient.Configuration(playlist: playlist))
            do {
                try await withConnectionTimeout {
                    // Handshake + profile doubles as the connection test.
                    let profile = try await client.authenticate()
                    playlist.userStatus = profile.status
                    playlist.expDate = profile.expDate
                    insertAndFinish(playlist)
                }
            } catch {
                errorMessage = Self.verboseError(error, context: "Stalker portal \(portal)")
                isLoading = false
            }
        }
    }

    private func addStremioPlaylist() {
        isLoading = true
        errorMessage = nil

        let playlistName = trimmedName.isEmpty ? "My Addon" : trimmedName
        let url = stremioURL.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let client = StremioClient()
                let manifest = try await client.fetchManifest(from: url)
                guard let normalized = StremioURL.normalize(url) else {
                    errorMessage = StremioError.invalidURL.localizedDescription
                    isLoading = false
                    return
                }
                let playlist = Playlist(name: playlistName, stremioURL: normalized.absoluteString)
                playlist.name = manifest.name
                insertAndFinish(playlist)
            } catch {
                errorMessage = Self.verboseError(error, context: "Stremio manifest \(url)")
                isLoading = false
            }
        }
    }

    private func insertAndFinish(_ playlist: Playlist) {
        modelContext.insert(playlist)
        // Set up the playlist's EPG source so the guide refreshes on its own
        // schedule — EPG is no longer part of the content sync.
        EPGSourceReconciler.reconcile(playlist, in: modelContext)
        // Persist immediately so the ContentSyncManager actor's
        // separate ModelContext can fetch the playlist. Without this
        // the autosave is deferred and the sync's fresh context
        // fetches nil, silently completing without syncing.
        try? modelContext.save()
        isLoading = false
        // Only dismiss when presented modally (e.g. the Settings
        // sheet). On first launch LoginView is the window's root
        // content, where dismiss() closes the window on macOS and
        // leaves the app with no visible window. Inserting the
        // playlist already swaps the root over to MainTabView via
        // ContentView's @Query.
        if isModal {
            dismiss()
        }
    }

    // MARK: - Verbose Error Formatting

    /// Produces a detailed, user-readable error message that includes the
    /// underlying cause. Users can screenshot this and send it for support
    /// without needing Xcode or Console.app.
    private static func verboseError(_ error: Error, context: String) -> String {
        let base: String
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                base = "Connection timed out. The server didn't respond within 15 seconds."
            case .cannotConnectToHost:
                base = "Can't connect to server. Check the URL and make sure the server is online."
            case .notConnectedToInternet:
                base = "No internet connection. Check your Wi-Fi or cellular data."
            case .cannotFindHost:
                base = "Server not found. The URL may be incorrect (check for typos)."
            case .secureConnectionFailed:
                base = "SSL/TLS error. The server's certificate is invalid or expired."
            case .networkConnectionLost:
                base = "Connection lost during the request. Try again."
            default:
                base = "Network error: \(urlError.localizedDescription) (code \(urlError.code.rawValue))"
            }
        } else if let xtreamError = error as? XtreamError {
            switch xtreamError {
            case .invalidURL:
                base = "Invalid server URL. Make sure it starts with http:// or https:// and includes the port."
            case .serverError(let code):
                base = "Server returned HTTP \(code). \(code == 403 ? "Access denied — check credentials or IP restrictions." : code == 404 ? "API endpoint not found — check the URL." : "Server error.")"
            case .decodingError:
                base = "Server response wasn't valid JSON. The URL may not be an Xtream-compatible panel."
            default:
                base = xtreamError.localizedDescription
            }
        } else {
            base = error.localizedDescription
        }
        return "\(base)\n\n[\(context)]"
    }
}

// MARK: - Connection-test timeout

private extension LoginView {
    struct ConnectionTimeoutError: LocalizedError {
        var errorDescription: String? {
            String(localized: "The connection timed out. Check the URL and your network, then try again.")
        }
    }

    /// Runs an add-playlist connection test under an overall deadline, cancelling
    /// the in-flight request and surfacing a timeout when it's exceeded.
    ///
    /// Each client has its own per-request timeout and (for Xtream) retry/backoff
    /// tuned for *sync*, where retries matter; left unbounded, a wrong URL or
    /// dead host can hang the add sheet for ~30–90s on a spinner with no way out.
    /// This caps the test (default 20s) without weakening the sync path.
    func withConnectionTimeout(_ seconds: Double = 20, _ operation: @escaping () async throws -> Void) async throws {
        let work = Task { try await operation() }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(seconds))
            work.cancel()
        }
        defer { watchdog.cancel() }
        do {
            try await work.value
        } catch {
            if work.isCancelled { throw ConnectionTimeoutError() }
            throw error
        }
    }
}

// MARK: - Local file import (iOS / macOS)

#if !os(tvOS)
    private extension LoginView {
        static var playlistFileTypes: [UTType] {
            var types: [UTType] = [.m3uPlaylist]
            if let m3u8 = UTType(filenameExtension: "m3u8") {
                types.append(m3u8)
            }
            return types
        }

        /// Copies the picked file into the app's Application Support directory
        /// so it stays readable across launches (the picker's URL is outside
        /// our sandbox and its security scope doesn't persist), then points the
        /// playlist URL field at the copy.
        func handleFileImport(_ result: Result<URL, Error>) {
            switch result {
            case let .success(pickedURL):
                let accessing = pickedURL.startAccessingSecurityScopedResource()
                defer {
                    if accessing { pickedURL.stopAccessingSecurityScopedResource() }
                }
                do {
                    let directory = try FileManager.default
                        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                        .appendingPathComponent("Playlists", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let destination = directory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(pickedURL.pathExtension.isEmpty ? "m3u" : pickedURL.pathExtension)
                    try FileManager.default.copyItem(at: pickedURL, to: destination)
                    m3uURL = destination.absoluteString
                    if trimmedName.isEmpty {
                        name = pickedURL.deletingPathExtension().lastPathComponent
                    }
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }
#endif

#Preview("Empty") {
    LoginView()
}

#Preview("With Error") {
    LoginView()
    // Note: error state is managed internally, shown via the errorMessage field.
    // In previews this can be simulated by setting initial state.
}
