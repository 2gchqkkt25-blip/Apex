//
//  CrossSourcePickerView.swift
//  Apex
//
//  A modal sheet that lets users choose which configured source (playlist or
//  media server) to play a movie or series from when the same title exists
//  in multiple places.
//

import SwiftData
import SwiftUI

/// The source list handed to the sheet. The rows travel with the sheet, so the
/// first time it opens it already has Xtream and Jellyfin instead of an empty list.
struct CrossSourcePrompt: Identifiable {
    let id = UUID()
    let items: [HomeMediaItem]
    let currentID: String
    let playlists: [Playlist]
    let mediaServers: [MediaServer]
    /// Set when Jellyfin, Emby, or Plex still needs a lookup. The sheet opens
    /// with the sources already on disk and fills this in behind the list.
    var lookupMovie: Movie?
    var lookupSeries: Series?
}

// MARK: - Row data (top-level to avoid nested-type inference issues)

struct CrossSourceRowData: Identifiable {
    let id: String
    let item: HomeMediaItem
    let displayName: String
    let badgeLabel: String?
    let isMediaServer: Bool
    let qualityHint: String?
    let posterURL: URL?
    let contentTitle: String
    let isCurrent: Bool
}

// MARK: - Picker view

struct CrossSourcePickerView: View {
    let currentID: String
    let playlists: [Playlist]
    let mediaServers: [MediaServer]
    let onSelect: (HomeMediaItem) -> Void
    let onCancel: () -> Void
    let lookupMovie: Movie?
    let lookupSeries: Series?

    @Environment(\.modelContext) private var modelContext
    @State private var items: [HomeMediaItem]
    @State private var isSearching: Bool
    #if os(tvOS)
        @FocusState private var focusedID: String?
    #endif

    init(
        prompt: CrossSourcePrompt,
        onSelect: @escaping (HomeMediaItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        currentID = prompt.currentID
        playlists = prompt.playlists
        mediaServers = prompt.mediaServers
        self.onSelect = onSelect
        self.onCancel = onCancel
        lookupMovie = prompt.lookupMovie
        lookupSeries = prompt.lookupSeries
        _items = State(initialValue: prompt.items)
        _isSearching = State(initialValue: prompt.lookupMovie != nil || prompt.lookupSeries != nil)
    }

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            phoneBody
        #endif
    }

    #if os(tvOS)
        /// A solid card over a dim scrim. The system sheet on Apple TV is a large
        /// blurred panel, so this is presented full screen with a clear cover.
        private var tvBody: some View {
            let rows = computeRows()
            return ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose a source")
                            .font(.system(size: 28, weight: .bold))
                        if let title = rows.first?.contentTitle, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                    FittingScrollView(maxHeight: 380) {
                        VStack(spacing: 8) {
                            if rows.isEmpty, !isSearching {
                                Text("No sources found for this title")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            }
                            ForEach(rows) { row in
                                Button(action: { onSelect(row.item) }) {
                                    tvRow(row)
                                }
                                .buttonStyle(TVSourceRowButtonStyle())
                                .focused($focusedID, equals: row.id)
                            }
                            if isSearching {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text("Checking media servers…")
                                        .font(.system(size: 18, weight: .medium))
                                }
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    Text("Press Menu to close")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(22)
                .frame(width: 640)
                .background(tvCardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
            }
            .presentationBackground(.clear)
                .onAppear { focusFirstRow(in: rows) }
                .defaultFocus($focusedID, rows.first?.id, priority: .userInitiated)
            .onChange(of: items.count) { _, _ in
                focusFirstRow(in: computeRows())
            }
            .onExitCommand(perform: onCancel)
            .task { await loadRemainingSources() }
        }

        private var tvCardColor: Color {
            Color(red: 0.12, green: 0.12, blue: 0.14)
        }

        private func tvRow(_ row: CrossSourceRowData) -> some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let badge = row.badgeLabel {
                            Text(badge)
                                .font(.system(size: 15, weight: .semibold))
                                .opacity(0.72)
                        }
                        if let hint = row.qualityHint {
                            Text(hint)
                                .font(.system(size: 15))
                                .opacity(0.55)
                        }
                    }
                }
                Spacer(minLength: 8)
                if row.isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func focusFirstRow(in rows: [CrossSourceRowData]) {
            guard focusedID == nil || !rows.contains(where: { $0.id == focusedID }) else { return }
            focusedID = rows.first?.id
        }
        #else
        @Environment(ThemeManager.self) private var themeManager

        private var phoneBody: some View {
            NavigationStack {
                ScrollView {
                    let rows = computeRows()
                    VStack(spacing: 0) {
                        if rows.isEmpty, !isSearching {
                            Text("No sources found for this title")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, minHeight: 160)
                        }
                        ForEach(rows) { row in
                            Button(action: { onSelect(row.item) }) {
                                HStack(spacing: 12) {
                                    PosterImage(url: row.posterURL)
                                        .frame(width: 48, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.displayName)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text(row.contentTitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.72))
                                            .lineLimit(2)
                                        HStack(spacing: 6) {
                                            if let badge = row.badgeLabel {
                                                BadgeView(
                                                    label: badge,
                                                    isMediaServer: row.isMediaServer,
                                                    colors: themeManager.colors
                                                )
                                            }
                                            if let hint = row.qualityHint {
                                                Text(hint)
                                                    .font(.caption2)
                                                    .foregroundStyle(.white.opacity(0.6))
                                            }
                                        }
                                    }
                                    Spacer()
                                    if row.isCurrent {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(themeManager.colors.accent)
                                            .font(.title3)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 72)
                        }
                        if isSearching {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking media servers…")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .navigationTitle("Choose Source")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
            }
            .frame(minWidth: 440, idealWidth: 520, minHeight: 360, idealHeight: 460)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12))
            .task { await loadRemainingSources() }
        }
    #endif

    /// Jellyfin, Emby, and Plex are asked after the sheet is on screen, so Play
    /// does not sit idle while a server search runs.
    private func loadRemainingSources() async {
        let found: [HomeMediaItem]
        if let lookupMovie {
            found = await OtherSources.resolvedSources(for: lookupMovie, in: modelContext)
        } else if let lookupSeries {
            found = await OtherSources.resolvedSources(for: lookupSeries, in: modelContext)
        } else {
            return
        }
        if !found.isEmpty { items = found }
        isSearching = false
    }

    // MARK: - Pure row computation (no @State, no closures in body)

    private func computeRows() -> [CrossSourceRowData] {
        var result: [CrossSourceRowData] = []
        result.reserveCapacity(items.count)
        for item in items {
            let uuid = ownerUUID(for: item)
            var pName: String? = nil
            var sName: String? = nil
            var isMS = false
            if let uuid {
                for p in playlists where p.id.uuidString.caseInsensitiveCompare(uuid) == .orderedSame {
                    pName = p.name
                    break
                }
                if pName == nil {
                    for s in mediaServers where s.id.uuidString.caseInsensitiveCompare(uuid) == .orderedSame {
                        sName = s.name
                        isMS = true
                        break
                    }
                }
            }
            let badge = badgeLabel(uuid: uuid)
            let hint = qualityHint(for: item)
            let poster = posterURL(for: item)
            let named = [pName, sName].compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }.first
            let name = named ?? badge ?? "Source"
            result.append(CrossSourceRowData(
                id: item.id,
                item: item,
                displayName: name,
                badgeLabel: badge,
                isMediaServer: isMS,
                qualityHint: hint,
                posterURL: poster,
                contentTitle: item.title,
                isCurrent: item.id == currentID
            ))
        }
        return result
    }

    private func ownerUUID(for item: HomeMediaItem) -> String? {
        switch item {
        case .movie(let m):
            let parts = m.id.components(separatedBy: "-movie-")
            return parts.count >= 2 ? parts[0] : nil
        case .series(let s):
            let parts = s.id.components(separatedBy: "-series-")
            return parts.count >= 2 ? parts[0] : nil
        default:
            return nil
        }
    }

    private func badgeLabel(uuid: String?) -> String? {
        guard let uuid else { return nil }
        for p in playlists where p.id.uuidString.caseInsensitiveCompare(uuid) == .orderedSame {
            switch p.sourceType {
            case .xtream: return "Xtream"
            case .m3u: return "M3U"
            case .stalker: return "Stalker"
            }
        }
        for s in mediaServers where s.id.uuidString.caseInsensitiveCompare(uuid) == .orderedSame {
            return s.kind.displayName
        }
        return nil
    }

    private func qualityHint(for item: HomeMediaItem) -> String? {
        switch item {
        case .movie(let m):
            guard let d = m.durationSecs, d > 0 else { return nil }
            return "\(d / 60) min"
        case .series(let s):
            guard let y = s.releaseDate?.prefix(4) else { return nil }
            return String(y)
        default:
            return nil
        }
    }

    private func posterURL(for item: HomeMediaItem) -> URL? {
        switch item {
        case .movie(let m): return m.streamIcon.flatMap(URL.init(string:))
        case .series(let s): return s.cover.flatMap(URL.init(string:))
        default: return nil
        }
    }
}

extension View {
    /// iPhone and Mac keep the system sheet. Apple TV draws the picker’s own card
    /// so the large blurred system panel is not used.
    func crossSourcePicker(
        item: Binding<CrossSourcePrompt?>,
        onSelect: @escaping (HomeMediaItem) -> Void
    ) -> some View {
        modifier(CrossSourcePickerPresenter(prompt: item, onSelect: onSelect))
    }
}

private struct CrossSourcePickerPresenter: ViewModifier {
    @Binding var prompt: CrossSourcePrompt?
    let onSelect: (HomeMediaItem) -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
            content.fullScreenCover(item: $prompt) { prompt in
                CrossSourcePickerView(
                    prompt: prompt,
                    onSelect: { item in
                        self.prompt = nil
                        onSelect(item)
                    },
                    onCancel: { self.prompt = nil }
                )
            }
        #else
            content.sheet(item: $prompt) { prompt in
                CrossSourcePickerView(
                    prompt: prompt,
                    onSelect: { item in
                        self.prompt = nil
                        onSelect(item)
                    },
                    onCancel: { self.prompt = nil }
                )
            }
        #endif
    }
}

#if os(tvOS)
    private struct TVSourceRowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            TVSourceRowBody(configuration: configuration)
        }

        private struct TVSourceRowBody: View {
            let configuration: ButtonStyleConfiguration
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isFocused ? Color.white : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
        }
    }
#endif

// MARK: - Poster (isolated CachedAsyncImage)

private struct PosterImage: View {
    let url: URL?
    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Color.gray.opacity(0.3)
            @unknown default:
                Color.gray.opacity(0.3)
            }
        }
    }
}

// MARK: - Badge (trivial leaf view)

private struct BadgeView: View {
    let label: String
    let isMediaServer: Bool
    let colors: ThemeColors
    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isMediaServer ? Color.orange.opacity(0.2) : colors.accent.opacity(0.2))
            .clipShape(Capsule())
            .foregroundStyle(isMediaServer ? .orange : colors.accent)
    }
}