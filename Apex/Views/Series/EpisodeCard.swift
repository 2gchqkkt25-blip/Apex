import SwiftUI

/// A wide episode row: 16:9 still on the left, title / runtime / synopsis on the
/// right, a resume progress bar and a play affordance.
struct EpisodeCard: View {
    let episode: Episode
    @Environment(ThemeManager.self) private var themeManager
    var onPlay: () -> Void
    var onPlayFromBeginning: (() -> Void)?
    var onToggleWatched: () -> Void = {}
    var onMarkPreviousWatched: () -> Void = {}
    var onMarkFollowingUnwatched: () -> Void = {}
    #if !os(tvOS)
        var onDownload: (() -> Void)?
        var onDeleteDownload: (() -> Void)?
        var downloadProgress: Double?
    #endif

    var body: some View {
        Button(action: { if episode.isProviderEpisode { onPlay() } }) {
            HStack(alignment: .top, spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text("E\(episode.episodeNum)" + (episode.title.isEmpty ? "" : " · \(episode.title)"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let metaLine {
                        Text(metaLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let plot = episode.plot, !plot.isEmpty {
                        Text(plot)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let progress = resumeFraction {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(themeManager.colors.accent)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!episode.isProviderEpisode)
        .apexContextMenu(episodeActions)
    }

    private var thumbnail: some View {
        ZStack(alignment: .topLeading) {
            CachedAsyncImage(url: URL(string: episode.movieImage ?? ""), maxPixelSize: 142) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty where episode.movieImage != nil:
                    Rectangle().fill(.fill.quaternary).overlay { ProgressView() }
                default:
                    Rectangle().fill(.fill.quaternary)
                        .overlay {
                            Text(placeholderTitle)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(6)
                        }
                }
            }
            .frame(width: 142, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            #if !os(tvOS)
                if let progress = downloadProgress {
                    downloadBadge(progress: progress)
                        .padding(5)
                } else if episode.downloadStatus == .completed {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.tint.opacity(0.85), in: Circle())
                        .padding(5)
                }
            #endif

            if episode.isProviderEpisode {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .opacity(0.9)
                    .frame(width: 142, height: 80)
            }
        }
        .frame(width: 142, height: 80)
    }

    #if !os(tvOS)
        private func downloadBadge(progress: Double) -> some View {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 2)
                    .frame(width: 16, height: 16)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: max(0.04, progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        // Matches the manager's 250 ms progress-publish cadence
                        // so the ring sweeps continuously between updates.
                        .animation(.linear(duration: 0.25), value: progress)
                        .frame(width: 16, height: 16)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(.white)
                        .scaleEffect(0.65)
                }
            }
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.55), in: Circle())
        }
    #endif

    private var episodeActions: [ApexContextAction] {
        guard episode.isProviderEpisode else { return [] }
        var actions: [ApexContextAction] = []
        if let playFromStart = onPlayFromBeginning, episode.watchProgress > 1 {
            actions.append(.button(String(localized: "Play from Beginning"), systemImage: "gobackward", perform: playFromStart))
            actions.append(.divider)
        }
        actions.append(.button(
            episode.isWatched ? String(localized: "Mark as Unwatched") : String(localized: "Mark as Watched"),
            systemImage: episode.isWatched ? "eye.slash" : "checkmark.circle",
            perform: onToggleWatched
        ))
        if episode.hasEarlierEpisodes {
            actions.append(.button(String(localized: "Mark All Previous as Watched"), systemImage: "checkmark.circle.fill", perform: onMarkPreviousWatched))
        }
        if episode.hasLaterWatchedEpisodes {
            actions.append(.button(String(localized: "Mark All Following as Unwatched"), systemImage: "arrow.counterclockwise.circle", perform: onMarkFollowingUnwatched))
        }
        #if !os(tvOS)
            actions.append(.divider)
            if episode.downloadStatus == .completed {
                actions.append(.button(String(localized: "Remove Download"), systemImage: "trash", isDestructive: true) {
                    onDeleteDownload?()
                })
            } else if downloadProgress == nil {
                actions.append(.button(
                    String(localized: "Download Episode"),
                    systemImage: "arrow.down.circle",
                    isEnabled: onDownload != nil
                ) {
                    onDownload?()
                })
            } else {
                actions.append(.button(String(localized: "Cancel Download"), systemImage: "xmark.circle", isDestructive: true) {
                    onDeleteDownload?()
                })
            }
        #endif
        return actions
    }

    private var placeholderTitle: String {
        if !episode.title.isEmpty { return episode.title }
        if let name = episode.series?.name, !name.isEmpty { return name }
        return "E\(episode.episodeNum)"
    }

    /// Air date and runtime joined on a single caption line, omitting whichever is missing.
    private var metaLine: String? {
        var parts = [
            DetailFormat.date(from: episode.airDate),
            DetailFormat.minutes(episode.durationSecs)
        ].compactMap(\.self)
        if !episode.isProviderEpisode {
            parts.insert(availabilityLabel, at: 0)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var availabilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let raw = episode.airDate, let parsed = formatter.date(from: raw) else {
            return "Not available"
        }
        return parsed > Date() ? "Upcoming" : "Not available"
    }

    private var resumeFraction: Double? {
        guard episode.watchProgress > 0,
              let duration = episode.durationSecs, duration > 0,
              !episode.isWatched else { return nil }
        return min(episode.watchProgress / Double(duration), 1)
    }
}

#if !os(tvOS)
    /// Reads `DownloadManager` state in a leaf view so download-progress ticks
    /// re-render only the episode rows, not the entire detail screen. Reading
    /// `activeDownloads` directly in `SeriesDetailView.episodesSection` made
    /// every progress update re-evaluate the whole body (hero, sections, all
    /// cards), which starved the main thread during active downloads.
    struct DownloadableEpisodeCard: View {
        let episode: Episode
        let playlist: Playlist?
        var onPlay: () -> Void
        var onPlayFromBeginning: (() -> Void)?
        var onToggleWatched: () -> Void
        var onMarkPreviousWatched: () -> Void
        var onMarkFollowingUnwatched: () -> Void

        /// Offline downloads are a Premium feature; free users get the paywall.
        @State private var premium = PremiumManager.shared
        @State private var showPaywall = false

        var body: some View {
            let downloads = DownloadManager.shared
            EpisodeCard(
                episode: episode,
                onPlay: onPlay,
                onPlayFromBeginning: onPlayFromBeginning,
                onToggleWatched: onToggleWatched,
                onMarkPreviousWatched: onMarkPreviousWatched,
                onMarkFollowingUnwatched: onMarkFollowingUnwatched,
                onDownload: playlist.flatMap { playlist in
                    // Stalker portals don't support offline downloads (short-lived
                    // stream URLs), so the download affordance is hidden for them.
                    guard playlist.supportsDownloads else { return nil }
                    return {
                        if premium.isPremium {
                            DownloadManager.shared.startDownload(episode: episode, playlist: playlist)
                        } else {
                            showPaywall = true
                        }
                    }
                },
                onDeleteDownload: { DownloadManager.shared.deleteLocalFile(id: episode.id) },
                downloadProgress: downloads.activeDownloads[episode.id].map(\.fractionCompleted)
                    ?? (downloads.pendingIDs.contains(episode.id) ? 0 : nil)
            )
            .paywall(isPresented: $showPaywall, highlight: .downloads)
        }
    }
#endif
