//
//  SyncProgressView.swift
//  Apex
//
//  Branded step-by-step progress for ContentSyncManager + inline EPG refresh.
//  Two presentations share this view: the blocking auto-sync cover (autoStart)
//  and the manual "Sync Now" flow.
//

import SwiftData
import SwiftUI

struct SyncProgressView: View {
    let playlist: Playlist

    /// When true the sync begins on appear and the sheet dismisses itself once
    /// it finishes successfully — used for the blocking auto-sync cover.
    let autoStart: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    @State private var progress = SyncProgress()
    @State private var phase: Phase
    @State private var syncError: String?
    @State private var syncTask: Task<Void, Never>?

    init(playlist: Playlist, autoStart: Bool = false) {
        self.playlist = playlist
        self.autoStart = autoStart
        _progress = State(initialValue: SyncProgress(steps: SyncStep.steps(for: playlist.sourceType)))
        _phase = State(initialValue: autoStart ? .syncing : .ready)
    }

    private enum Phase {
        case ready
        case syncing
        case finished
        case failed
    }

    private var includesGuideStep: Bool {
        SyncStep.includesEPG(for: playlist.sourceType)
    }

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            standardBody
        #endif
    }

    private var headerTitle: LocalizedStringKey {
        switch phase {
        case .ready: "Ready to sync"
        case .syncing:
            includesGuideStep ? "Updating library & guide" : "Syncing your library"
        case .finished: "You're all set"
        case .failed: "Sync failed"
        }
    }

    private var headerSubtitle: LocalizedStringKey {
        switch phase {
        case .ready: "Content and TV guide refresh together."
        case .syncing: "This may take a few minutes…"
        case .finished:
            includesGuideStep ? "Your playlist and TV guide are up to date." : "Your playlist is up to date."
        case .failed: "Something went wrong. You can try again."
        }
    }

    // MARK: - Drive sync

    private func startSync() {
        progress = SyncProgress(steps: SyncStep.steps(for: playlist.sourceType))
        syncError = nil
        phase = .syncing

        syncTask = Task {
            // Suppress background EPG triggers (launch `syncIfDue`, Sync Now) for
            // the whole flow so a second guide refresh can't stack on top of the
            // content sync and blow the memory limit.
            await EPGSyncService.shared.beginExclusiveSync()
            defer { Task { @MainActor in EPGSyncService.shared.endExclusiveSync() } }
            do {
                let syncManager = ContentSyncManager(modelContainer: modelContext.container)
                try await syncManager.syncPlaylist(playlist, progress: progress, full: true)

                if SyncStep.includesEPG(for: playlist.sourceType) {
                    try Task.checkCancellation()
                    #if os(tvOS)
                    // Run a lightweight inline EPG pass on tvOS using only the 3
                    // lightest feeds (~30MB total). This is small enough to parse
                    // without jetsam risk while giving the store data for most
                    // channels before the user opens Live TV. A background pass
                    // with remaining feeds fills gaps later.
                    await runEPGStep(mode: .tvOSQuick)
                    #else
                    await runEPGStep()
                    #endif
                }

                await schedulePostSyncIndexing()
                await MainActor.run {
                    phase = .finished
                    if autoStart { dismiss() }
                }
            } catch is CancellationError {
                // User aborted — sheet is dismissing.
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    syncError = error.localizedDescription
                    phase = .failed
                }
            }
        }
    }

    @MainActor
    private func runEPGStep(mode: EPGSyncMode = .withPlaylist) async {
        progress.start(.epgGuide)
        let epgPoll = Task {
            while !Task.isCancelled {
                if let label = EPGSyncService.shared.syncProgressLabel {
                    progress.update(
                        detail: label,
                        fraction: EPGSyncService.shared.syncProgress ?? 0
                    )
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { epgPoll.cancel() }

        _ = await EPGSyncService.shared.syncAwaiting(
            container: modelContext.container,
            mode: mode
        ) { fraction, label in
            let pct = Int(((fraction ?? 0) * 100).rounded())
            let detail: String
            if let label, !label.isEmpty {
                detail = label.contains("%") ? label : "\(pct)% · \(label)"
            } else {
                detail = "\(pct)%"
            }
            progress.update(detail: detail, fraction: fraction ?? 0)
        }
        progress.complete(.epgGuide)
        EPGSyncService.shared.forceGuideRefresh()
    }

    /// Indexing (all platforms) plus, on tvOS, the deferred guide refresh.
    private func schedulePostSyncIndexing() async {
        #if os(tvOS)
        await MainActor.run {
            ContentIndexingService.shared.kick(after: .seconds(20))
            // Update Top Shelf content so the extension shows fresh data
            TopShelfDataWriter.update(container: modelContext.container)
        }
        // Run the guide import well after the sheet dismisses so the content
        // sync's memory is fully released first, giving the feed parse the whole
        // budget. Uses the lighter bundled feed set (US, no US_LOCALS1). The
        // inline quick pass already populated the store with the 3 lightest
        // feeds; this background pass fills remaining channels from the rest of
        // the bundled set. 10s is enough headroom for ARC to reclaim buffers.
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(10))
            await MainActor.run {
                EPGSyncService.shared.syncBundledInBackground()
            }
        }
        #else
        await MainActor.run {
            ContentIndexingService.shared.kick(after: .seconds(3))
        }
        #endif
    }

    private func abortSync() {
        syncTask?.cancel()
        syncTask = nil
        EPGSyncService.shared.cancelActiveSync(reason: "playlist sync cancelled")
        dismiss()
    }
}

// MARK: - iOS / macOS layout

#if !os(tvOS)

    private extension SyncProgressView {
        var standardBody: some View {
            ZStack {
                ApexSyncBackground()

                VStack(spacing: 0) {
                    brandedHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(progress.steps) { step in
                                ApexSyncStepRow(
                                    step: step,
                                    state: progress.state(for: step),
                                    detail: progress.currentStep == step ? progress.stepDetail : "",
                                    fraction: progress.currentStep == step ? progress.stepFraction : 0
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }

                    footer
                        .padding(24)
                }
            }
            .preferredColorScheme(.dark)
            .interactiveDismissDisabled(phase == .syncing)
            .task {
                if autoStart, phase != .finished {
                    startSync()
                }
            }
        }

        var brandedHeader: some View {
            VStack(spacing: 20) {
                ApexSyncHero(
                    progress: progress.overallFraction,
                    isAnimating: phase == .syncing
                )

                VStack(spacing: 6) {
                    Text("Apex")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ApexBrandColors.logoGradient)
                        .textCase(.uppercase)
                        .tracking(2)

                    Text(headerTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }

        @ViewBuilder
        var footer: some View {
            switch phase {
            case .ready:
                Button(action: startSync) {
                    Label("Start Sync", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ApexBrandColors.blue)
                .controlSize(.large)

                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.6))

            case .syncing:
                VStack(spacing: 12) {
                    Button("Cancel") { abortSync() }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)

            case .finished:
                Button { dismiss() } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ApexBrandColors.blue)
                .controlSize(.large)

            case .failed:
                VStack(spacing: 12) {
                    if let syncError {
                        Text(syncError)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                    Button(action: startSync) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ApexBrandColors.blue)
                    .controlSize(.large)

                    Button("Continue Without Syncing") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

#endif

// MARK: - tvOS layout

#if os(tvOS)

    private extension SyncProgressView {
        var tvBody: some View {
            ZStack {
                ApexSyncBackground()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 48) {
                        tvBrandedHeader

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(progress.steps) { step in
                                ApexSyncStepRow(
                                    step: step,
                                    state: progress.state(for: step),
                                    detail: progress.currentStep == step ? progress.stepDetail : "",
                                    fraction: progress.currentStep == step ? progress.stepFraction : 0
                                )
                            }
                        }

                        tvFooter
                    }
                    .frame(maxWidth: TVSettingsMetrics.contentMaxWidth, alignment: .leading)
                    .padding(.horizontal, 80)

                    Spacer(minLength: 0)
                }
            }
            .preferredColorScheme(.dark)
            .interactiveDismissDisabled(phase == .syncing)
            .task {
                if autoStart, phase != .finished {
                    startSync()
                }
            }
        }

        var tvBrandedHeader: some View {
            HStack(alignment: .center, spacing: 48) {
                ApexSyncHeroTV(
                    progress: progress.overallFraction,
                    isAnimating: phase == .syncing
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Apex")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ApexBrandColors.logoGradient)
                        .textCase(.uppercase)
                        .tracking(3)

                    Text(headerTitle)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)

                    Text(headerSubtitle)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer(minLength: 0)
            }
        }

        @ViewBuilder
        var tvFooter: some View {
            switch phase {
            case .ready:
                HStack(spacing: 24) {
                    Button(action: startSync) {
                        Label("Start Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(TVSettingsActionButtonStyle(prominent: true))

                    Button("Cancel") { dismiss() }
                        .buttonStyle(TVSettingsActionButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .center)

            case .syncing:
                VStack(spacing: 32) {
                    Button("Cancel") { abortSync() }
                        .buttonStyle(TVSettingsActionButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .center)

            case .finished:
                Button("Done") { dismiss() }
                    .buttonStyle(TVSettingsActionButtonStyle(prominent: true))
                    .frame(maxWidth: .infinity, alignment: .center)

            case .failed:
                VStack(spacing: 24) {
                    if let syncError {
                        Text(verbatim: syncError)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 640)
                    }

                    HStack(spacing: 24) {
                        Button(action: startSync) {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(TVSettingsActionButtonStyle(prominent: true))

                        Button("Continue Without Syncing") { dismiss() }
                            .buttonStyle(TVSettingsActionButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

#endif

#Preview("Ready") {
    let container = previewContainer()
    let playlist = PreviewData.samplePlaylist
    return SyncProgressView(playlist: playlist)
        .modelContainer(container)
        .environment(ThemeManager.shared)
}
