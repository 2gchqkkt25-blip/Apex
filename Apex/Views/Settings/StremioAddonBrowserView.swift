//
//  StremioAddonBrowserView.swift
//  Apex
//
//  Browse and install community Stremio addons with one tap. Fetches the
//  official addon collection from Stremio's API, displays them in a searchable
//  list, and lets the user install any addon as a playlist.
//

import SwiftData
import SwiftUI

struct StremioAddonBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<Playlist> { $0.sourceTypeRaw == "stremio" })
    private var installedPlaylists: [Playlist]

    @State private var addons: [StremioAddonEntry] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var filterType: AddonFilterType = .all
    @State private var errorMessage: String?

    private enum AddonFilterType: String, CaseIterable {
        case all = "All"
        case catalog = "Catalogs"
        case streams = "Streams"
    }

    private var filteredAddons: [StremioAddonEntry] {
        var result = addons
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query)
                    || ($0.description ?? "").lowercased().contains(query)
            }
        }
        switch filterType {
        case .all: break
        case .catalog:
            result = result.filter { $0.hasCatalogs }
        case .streams:
            result = result.filter { $0.hasStreams }
        }
        return result
    }

    /// URLs already installed, for showing the "Installed" badge.
    private var installedURLs: Set<String> {
        Set(installedPlaylists.compactMap { StremioURL.normalize($0.serverURL)?.absoluteString })
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading addons…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Addons",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                addonList
            }
        }
        .navigationTitle("Stremio Addons")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search addons")
        #endif
        .task {
            await loadAddons()
        }
    }

    private var addonList: some View {
        List {
            Section {
                Picker("Filter", selection: $filterType) {
                    ForEach(AddonFilterType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
            }

            Section {
                ForEach(filteredAddons) { addon in
                    addonRow(addon)
                }
            } header: {
                Text("\(filteredAddons.count) addons")
            }
        }
    }

    @ViewBuilder
    private func addonRow(_ addon: StremioAddonEntry) -> some View {
        let isInstalled = installedURLs.contains(addon.normalizedURL ?? "")
        HStack(spacing: 12) {
            // Addon icon
            AsyncImage(url: addon.logoURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(addon.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if isInstalled {
                        Text("Installed")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                if let desc = addon.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if addon.hasCatalogs {
                        Label("Catalog", systemImage: "square.grid.2x2")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if addon.hasStreams {
                        Label("Streams", systemImage: "play.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text("v\(addon.version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !isInstalled {
                Button("Install") {
                    installAddon(addon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func loadAddons() async {
        do {
            let fetched = try await StremioAddonCatalog.fetchOfficialAddons()
            await MainActor.run {
                addons = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func installAddon(_ addon: StremioAddonEntry) {
        let playlist = Playlist(name: addon.name, stremioURL: addon.transportUrl)
        modelContext.insert(playlist)
        try? modelContext.save()
    }
}

// MARK: - Addon Catalog Fetcher

enum StremioAddonCatalog {
    private static let collectionURL = URL(string: "https://api.strem.io/addonscollection.json")!

    static func fetchOfficialAddons() async throws -> [StremioAddonEntry] {
        var request = URLRequest(url: collectionURL)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        let raw = try JSONDecoder().decode([StremioAddonRaw].self, from: data)
        return raw.compactMap { StremioAddonEntry(raw: $0) }
    }
}

// MARK: - Models

struct StremioAddonEntry: Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let transportUrl: String
    let logoURL: URL?
    let types: [String]
    let resources: [String]

    var hasCatalogs: Bool { resources.contains("catalog") }
    var hasStreams: Bool { resources.contains("stream") }

    var normalizedURL: String? {
        StremioURL.normalize(transportUrl)?.absoluteString
    }

    init?(raw: StremioAddonRaw) {
        guard let manifest = raw.manifest else { return nil }
        self.id = manifest.id
        self.name = manifest.name
        self.version = manifest.version
        self.description = manifest.description
        self.transportUrl = raw.transportUrl
        self.logoURL = manifest.logo.flatMap { URL(string: $0) }
        self.types = manifest.types ?? []
        self.resources = manifest.resources?.compactMap { $0.stringValue } ?? []
    }
}

// MARK: - Raw JSON Models

struct StremioAddonRaw: Decodable {
    let transportUrl: String
    let manifest: StremioAddonManifestRaw?
}

struct StremioAddonManifestRaw: Decodable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let logo: String?
    let types: [String]?
    let resources: [StremioResourceRaw]?
}

/// Handles both string resources ("catalog") and object resources ({name: "stream", ...})
enum StremioResourceRaw: Decodable {
    case string(String)
    case object(StremioResourceObjectRaw)

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .object(let o): return o.name
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .object(try StremioResourceObjectRaw(from: decoder))
        }
    }
}

struct StremioResourceObjectRaw: Decodable {
    let name: String
}
