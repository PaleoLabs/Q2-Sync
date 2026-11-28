//
//  SyncCoordinator.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Runs one sync from start to finish for the UI, as a simple state
//  machine:
//
//      idle ──Sync──▶ planning ──▶ preview ──Apply──▶ running ──▶ finished
//                        │            │                  │
//                        └──▶ failed  └──Cancel──▶ idle  └──Cancel──▶ finished (cancelled)
//
//  HOW IT FITS
//  The Sync button calls `prepare`; the sync sheet shows the current
//  `phase`. All real work is done by the Core engine (SelectionResolver,
//  SyncPlanner, SyncSafety, SyncExecutor); this class only wires it to the
//  UI and to `DeviceMonitor` (for ejecting and saving device state).
//
//  SAFETY
//  • The library is re-read for every sync, and the "Mac looks empty"
//    check runs first; an unsafe library stops the sync before planning.
//  • The first sync for a device is never applied automatically.
//  • Nothing is written until the user clicks Sync in the preview.
//

import Foundation
import Observation

/// Everything needed to show a preview and later apply it.
struct SyncPreview {
    let plan: SyncPlan
    let manifest: SyncManifest
    let fileSystem: CardFileSystem
    let health: LibraryHealth
    let isFirstSync: Bool
    let availableBytes: Int64
    let deviceName: String
    let profile: DeviceProfile
    /// Mac folders copy-back must never write to (~/Music, media folder).
    let protectedFolders: [URL]
    /// Reads album artwork for the planned covers (read-only), if any.
    var artwork: (any AlbumArtworkProviding)? = nil

    /// Safety assessment for the user's current choices.
    func assessment(for options: SyncOptions) -> SafetyAssessment {
        SyncSafety.assess(plan: plan, health: health, isFirstSync: isFirstSync,
                          availableBytes: availableBytes, includeRemovals: options.applyRemovals,
                          cardOnlyActions: options.cardOnlyActions)
    }
}

/// Drives a sync and exposes its state to the UI.
@MainActor
@Observable
final class SyncCoordinator {

    /// Where the sync is in its lifecycle.
    enum Phase: Equatable {
        case idle
        case planning(String)
        case preview
        case running
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// The plan being previewed or applied.
    private(set) var preview: SyncPreview?

    /// The user's choices in the preview sheet.
    var options = SyncOptions()

    /// Live progress while running.
    private(set) var progress = SyncProgress()

    /// Seconds of copying left, once there's enough to estimate.
    private(set) var secondsRemaining: TimeInterval?

    /// Measures copying speed for `secondsRemaining`.
    @ObservationIgnored private var estimator = TimeRemainingEstimator()
    /// Measures the album-cover step, which isn't counted in bytes.
    @ObservationIgnored private var coverEstimator = TimeRemainingEstimator.forCovers()
    /// Measures the removal step, counted in files (#62).
    @ObservationIgnored private var removalEstimator = TimeRemainingEstimator.forRemovals()

    /// The result once finished.
    private(set) var report: SyncReport?

    /// The card being synced, kept so the result sheet can word its steps
    /// and tell whether that card is still connected.
    private(set) var deviceUUID: String?
    private(set) var connection = CardConnection.unknown

    /// `true` while ejecting from the result sheet.
    private(set) var isEjecting = false

    /// The running copy task, kept so Cancel can stop it.
    private var task: Task<Void, Never>?

    /// Bumped by each `prepare` and by `close`. Planning runs across
    /// several `await`s; when it resumes it checks this, so a cancelled
    /// or superseded plan is dropped instead of reopening the sheet (or,
    /// for auto-sync, being applied after the user pressed Cancel).
    @ObservationIgnored private var planningGeneration = 0

    /// What happened in an AUTOMATIC sync, for notifications.
    enum AutomaticEvent {
        case upToDate
        case needsReview([String])
        case finished(SyncReport)
        case failed(String)
    }

    /// `true` while the current sync was started automatically (auto-sync
    /// or a notification's "Sync Now").
    private(set) var isAutomatic = false

    /// Called with automatic syncs' outcomes (set by `AutoSyncController`).
    var onAutomaticEvent: ((AutomaticEvent) -> Void)?

    /// `true` while a sheet should be shown.
    var isPresentingSheet: Bool { phase != .idle }

    /// `true` while the card is being read (planning) or written (running).
    var isUsingCard: Bool {
        if case .planning = phase { return true }
        return phase == .running
    }

    // MARK: - Planning

    /// Re-reads the library, checks safety, scans the card and builds a plan.
    ///
    /// - Parameters:
    ///   - connected: The Q2 to sync.
    ///   - library: The library model (re-read here).
    ///   - devices: For the card's saved state.
    ///   - automatic: `true` for auto-sync: the plan is applied without
    ///     showing the preview ONLY if `AutoSyncPolicy` allows it;
    ///     otherwise the preview is shown and the user is notified.
    /// - Side effects: Reads the library and card. Never writes to the card.
    func prepare(connected: ConnectedDevice, library: LibraryModel, devices: DeviceMonitor,
                 audiobooks: (any AudiobookSource)? = nil, podcasts: (any PodcastSource)? = nil,
                 automatic: Bool = false) async {
        guard phase == .idle else { return }
        devices.flushPendingSave() // The selection on disk matches what's synced.
        planningGeneration += 1
        let generation = planningGeneration
        options = SyncOptions()
        report = nil
        deviceUUID = connected.device.volumeUUID
        connection = connected.connection
        isAutomatic = automatic

        let musicSelection = connected.device.effectiveSelection
        let snapshot: LibrarySnapshot
        let health: LibraryHealth
        if musicSelection.isEnabled {
            phase = .planning("Reading your Music library…")
            await library.load()
            guard isCurrentPlanning(generation) else { return }
            // A failed (or timed-out) read leaves the previous snapshot in place;
            // never sync from that stale copy.
            if case .failed(let message) = library.state {
                fail(message + " Nothing was synced.")
                return
            }
            guard let loaded = library.snapshot, let loadedHealth = library.health else {
                fail("Your Apple Music library couldn't be read, so nothing was synced.")
                return
            }
            // The "Mac looks empty" guard: stop before even looking at the card.
            if case .unsafe(let reason) = loadedHealth {
                fail(reason + " Nothing on the card was changed.")
                return
            }
            snapshot = loaded
            health = loadedHealth
        } else {
            // "Sync music" is off: the library isn't read, so an
            // audiobooks-only Q2 needs no Apple Music library. Nothing is
            // chosen; the songs Q2 Sync put on the card are planned as
            // removals, applied only with Remove Them (and auto-sync
            // stops for review). The "Mac looks empty" check guards
            // against a library that failed to read, which can't happen
            // here. The media folder from an earlier read stays protected.
            snapshot = LibrarySnapshot(tracks: [], playlists: [],
                                       mediaFolderURL: library.snapshot?.mediaFolderURL)
            health = .healthy
        }
        guard let cardRoot = connected.accessURL else {
            fail(connected.accessProblem ?? "Q2 Sync doesn't have access to the card.")
            return
        }

        // Audiobooks (Q2 Pod only): read Apple Books now, so the sync never
        // uses an old list. Without access, or if Books can't be read,
        // audiobooks are left as they are on the card.
        var books: [Audiobook]?
        var audiobookNote: String?
        let audiobookSelection = connected.device.effectiveAudiobooks
        if connected.device.profile.audiobooksFolderName != nil {
            if let audiobooks {
                phase = .planning("Reading Apple Books…")
                do {
                    books = try await audiobooks.loadAudiobooks()
                } catch AudiobookError.noBooksList {
                    books = []
                } catch {
                    audiobookNote = error.localizedDescription + " Audiobooks on the card weren't changed."
                }
                // The "looks healthy" check, like the Music library's: an
                // unreachable folder or chosen books missing in bulk leave
                // the card's audiobooks as they are.
                if let read = books, case .unsafe(let reason) = audiobooks.health(of: read, selection: audiobookSelection) {
                    books = nil
                    audiobookNote = reason + " Audiobooks on the card weren't changed."
                }
                guard isCurrentPlanning(generation) else { return }
            } else if audiobookSelection.isEnabled {
                audiobookNote = "Q2 Sync can't read Apple Books, so audiobooks weren't synced. Allow access on the Audiobooks tab."
            }
        }

        // Podcasts (Q2 Pod only): read the Podcasts app's downloads now,
        // like audiobooks. Without access, or if they can't be read,
        // podcasts are left as they are on the card.
        var shows: [PodcastShow]?
        var podcastNote: String?
        let podcastSelection = connected.device.effectivePodcasts
        if connected.device.profile.podcastsFolderName != nil {
            if let podcasts {
                phase = .planning("Reading the Podcasts app…")
                do {
                    shows = try await podcasts.loadPodcasts()
                } catch {
                    podcastNote = error.localizedDescription + " Podcasts on the card weren't changed."
                }
                // Likewise a missing database or downloads folder.
                if shows != nil, case .unsafe(let reason) = podcasts.health() {
                    shows = nil
                    podcastNote = reason + " Podcasts on the card weren't changed."
                }
                guard isCurrentPlanning(generation) else { return }
            } else if podcastSelection.isEnabled {
                podcastNote = "Q2 Sync can't read the Podcasts app, so podcasts weren't synced. Allow access on the Podcasts tab."
            }
        }

        phase = .planning("Checking the card…")
        do {
            let pathGuard = try PathGuard(
                cardRoot: cardRoot,
                expectedVolumeUUID: connected.device.volumeUUID,
                profile: connected.device.profile,
                extraProtectedFolders: [snapshot.mediaFolderURL].compactMap { $0 })
            let fileSystem = CardFileSystem(pathGuard: pathGuard)
            let selection = SelectionResolver.resolve(musicSelection, in: snapshot)
            let allSelectedIDs = Set((selection.tracksToSync + selection.skippedTracks).map(\.id))

            // Scanning thousands of card files happens off the main thread.
            let (manifest, plan) = try await Self.buildPlan(selection: selection, allSelectedIDs: allSelectedIDs,
                                                            snapshot: snapshot, musicEnabled: musicSelection.isEnabled,
                                                            fileSystem: fileSystem,
                                                            profile: connected.device.profile,
                                                            albumCovers: connected.device.effectiveAlbumCovers,
                                                            onlyChangedPlaylists: connected.device.effectiveImportOnlyChangedPlaylists,
                                                            reimportAllPlaylists: connected.device.reimportAllPlaylists == true,
                                                            books: books, audiobookSelection: audiobookSelection,
                                                            audiobookNote: audiobookNote,
                                                            shows: shows, podcastSelection: podcastSelection,
                                                            podcastNote: podcastNote)
            // Cancelled while the card was being scanned: drop the plan.
            guard isCurrentPlanning(generation) else { return }

            let isFirstSync = !connected.device.hasCompletedFirstSync

            // Read free space fresh: the value from when the card was
            // connected may be out of date.
            let freeNow = VolumeInfo.read(at: cardRoot)?.availableCapacity
                ?? connected.volume.availableCapacity ?? 0

            preview = SyncPreview(plan: plan, manifest: manifest, fileSystem: fileSystem, health: health,
                                  isFirstSync: isFirstSync,
                                  availableBytes: freeNow,
                                  deviceName: connected.device.name, profile: connected.device.profile,
                                  protectedFolders: [PathGuard.defaultHomeMusicFolder]
                                      + [snapshot.mediaFolderURL].compactMap { $0 },
                                  // Music off: no covers to write, and the library isn't opened.
                                  artwork: musicSelection.isEnabled
                                      ? library.artworkReader(for: Set(plan.coverWrites.map(\.trackID))) : nil)
            phase = .preview
            if automatic, let preview { decideAutomatically(preview, devices: devices) }
        } catch {
            guard isCurrentPlanning(generation) else { return }
            fail(error.localizedDescription)
        }
    }

    /// `true` if the planning run numbered `generation` is still the one
    /// the user is waiting for (not cancelled, not replaced by another).
    private func isCurrentPlanning(_ generation: Int) -> Bool {
        guard generation == planningGeneration, case .planning = phase else { return false }
        return true
    }

    /// For automatic syncs: apply, close as up to date, or stop and leave
    /// the preview open for review (see `AutoSyncPolicy`).
    private func decideAutomatically(_ preview: SyncPreview, devices: DeviceMonitor) {
        // Auto-sync never removes anything: removals stay off.
        options = SyncOptions()
        switch AutoSyncPolicy.decide(plan: preview.plan, assessment: preview.assessment(for: options)) {
        case .apply:
            apply(devices: devices)
        case .nothingToDo:
            close()
            onAutomaticEvent?(.upToDate)
        case .needsReview(let reasons):
            // Leave the preview open; the user decides from here.
            isAutomatic = false
            onAutomaticEvent?(.needsReview(reasons))
        }
    }

    /// Shows a failure, and reports it if the sync was automatic.
    private func fail(_ message: String) {
        phase = .failed(message)
        if isAutomatic { onAutomaticEvent?(.failed(message)) }
        isAutomatic = false
    }

    /// Loads the manifest, scans the card, plans, and finds card-only
    /// music (reading its tags), on a background thread.
    @concurrent
    private static func buildPlan(selection: ResolvedSelection, allSelectedIDs: Set<PersistentID>,
                                  snapshot: LibrarySnapshot, musicEnabled: Bool,
                                  fileSystem: CardFileSystem, profile: DeviceProfile,
                                  albumCovers: Bool, onlyChangedPlaylists: Bool,
                                  reimportAllPlaylists: Bool,
                                  books: [Audiobook]?, audiobookSelection: AudiobookSelection,
                                  audiobookNote: String?,
                                  shows: [PodcastShow]?, podcastSelection: PodcastSelection,
                                  podcastNote: String?) async throws
        -> (SyncManifest, SyncPlan) {
        let manifest = try SyncManifest.load(from: fileSystem)
        // The card is listed once (slow over the Q2's USB); the music and
        // playlist folders are taken from that listing.
        let wholeCard = CardScanner.scan(folder: "", on: fileSystem)
        let cardFiles = CardScanner.files(in: profile.musicFolderName, from: wholeCard)
        let playlistFiles = CardScanner.files(in: profile.playlistFolderName, from: wholeCard)
        let plan = SyncPlanner.plan(selection: selection, allSelectedIDs: allSelectedIDs, manifest: manifest,
                                    cardFiles: cardFiles, playlistFolderFiles: playlistFiles,
                                    // Music off: every Q2 Sync song is a removal, not an
                                    // "orphan" missing from an (unread) library.
                                    libraryIDs: musicEnabled ? Set(snapshot.tracks.map(\.id)) : nil,
                                    layout: CardLayout(profile: profile), albumCovers: albumCovers)
        var adjusted = plan

        // Card-only music anywhere on the card (reserved items excluded).
        var cardOnly = CardOnlyFinder.find(allCardFiles: wholeCard, manifest: manifest,
                                           orphanedEntries: plan.orphanedEntries,
                                           adoptedPaths: plan.adoptions.map(\.path), profile: profile)
        await AudioTagReader.fillTags(&cardOnly, cardRoot: fileSystem.pathGuard.cardRoot)
        CardOnlyFinder.markLibraryMatches(&cardOnly, snapshot: snapshot)
        adjusted.cardOnly = cardOnly
        // Music copied to the card by hand: adopt identical copies instead
        // of copying the same songs again.
        CardOnlyFinder.adoptIdenticalCopies(in: &adjusted, musicFolderName: profile.musicFolderName)

        // Audiobooks, in their own reserved folder (see AudiobookSync.swift).
        if let folderName = profile.audiobooksFolderName {
            if let books {
                adjusted.audiobooks = AudiobookPlanner.plan(books: books, selection: audiobookSelection,
                                                            manifest: manifest,
                                                            card: AudiobookCardListing.scan(on: fileSystem),
                                                            folderName: folderName)
            }
            if let audiobookNote { adjusted.audiobooks.note = audiobookNote }
        }

        // Podcasts, in their own reserved folder (see PodcastSync.swift).
        // Without a fresh list (no access, or a read error) nothing is
        // planned, so no episode is copied or removed.
        if let folderName = profile.podcastsFolderName {
            if let shows {
                adjusted.podcasts = PodcastPlanner.plan(shows: shows, selection: podcastSelection,
                                                        manifest: manifest,
                                                        card: CardFolderListing.scan(folderName: folderName,
                                                                                     on: fileSystem),
                                                        folderName: folderName)
            }
            if let podcastNote { adjusted.podcasts.note = podcastNote }
        }

        adjusted.playlistPlan.onlyChangedForImport = onlyChangedPlaylists
        adjusted.playlistPlan.reimportAll = reimportAllPlaylists
        PlaylistWriter.dropUnchangedWrites(in: &adjusted, manifest: manifest, profile: profile) { path in
            try? Data(contentsOf: fileSystem.urlForReading(path))
        }
        return (manifest, adjusted)
    }

    // MARK: - Applying

    /// Applies the previewed plan. The preview sheet only enables this when
    /// the safety assessment allows it.
    ///
    /// - Parameter devices: For ejecting and saving state afterwards.
    func apply(devices: DeviceMonitor) {
        guard phase == .preview, let preview, preview.assessment(for: options).canApply else { return }
        phase = .running
        progress = SyncProgress(totalOperations: 0, totalBytes: preview.plan.allBytesToCopy)
        secondsRemaining = nil
        estimator = TimeRemainingEstimator()
        coverEstimator = .forCovers()
        removalEstimator = .forRemovals()
        var executor = SyncExecutor(fileSystem: preview.fileSystem, deviceName: preview.deviceName)
        executor.artwork = preview.artwork
        executor.recoveryCopier = RecoveryCopier(stagingFolder: RecoveryCopier.defaultStagingFolder,
                                                 protectedFolders: preview.protectedFolders)
        let options = options
        let configuredExecutor = executor

        // Progress arrives on a background thread; hop to the main actor
        // before touching UI state. `[weak self]` means neither this nor
        // the task below keeps the coordinator alive on its own.
        let reportProgress: @Sendable (SyncProgress) -> Void = { [weak self] update in
            guard let self else { return }
            Task { @MainActor in
                self.progress = update
                let now = ProcessInfo.processInfo.systemUptime
                if update.isRemoving {
                    self.secondsRemaining = self.removalEstimator.update(bytesCopied: UInt64(update.removalsDone),
                                                                         totalBytes: UInt64(update.removalsTotal), at: now)
                } else if update.isAddingCovers {
                    self.secondsRemaining = self.coverEstimator.update(bytesCopied: UInt64(update.coversDone),
                                                                       totalBytes: UInt64(update.coversTotal), at: now)
                } else {
                    self.secondsRemaining = self.estimator.update(bytesCopied: update.bytesCopied,
                                                                  totalBytes: update.totalBytes, at: now)
                }
            }
        }

        task = Task { [weak self] in
            let result = await configuredExecutor.run(plan: preview.plan, manifest: preview.manifest,
                                                      options: options, onProgress: reportProgress)
            await self?.finish(with: result, devices: devices)
        }
    }

    /// Records the result. On full success, saves the device state. The
    /// card is NOT ejected automatically: the result sheet offers Eject, so
    /// you can keep it connected to sync again.
    private func finish(with result: SyncReport, devices: DeviceMonitor) async {
        report = result
        task = nil
        if result.succeeded {
            devices.markSyncCompleted()
            // A requested full re-import has now been put up.
            if preview?.plan.playlistPlan.reimportAll == true { devices.setReimportAllPlaylists(false) }
        }
        // The card changed: update the capacity bar's numbers.
        devices.reloadCardInfo()
        if isAutomatic { onAutomaticEvent?(.finished(result)) }
        isAutomatic = false
        phase = .finished
    }

    /// Ejects the card when the user clicks Eject on the result sheet, then
    /// closes the sheet. If ejecting fails, the card stays mounted and the
    /// sheet stays open, showing `DeviceMonitor`'s error.
    func ejectAfterSync(devices: DeviceMonitor) async {
        isEjecting = true
        let ejected = await devices.eject()
        isEjecting = false
        if ejected { close() }
    }

    /// Stops a running sync (finishes the current chunk, then stops), or
    /// closes the preview without changing anything.
    func cancel() {
        switch phase {
        case .running: task?.cancel()
        default: close()
        }
    }

    /// Closes the sheet and resets.
    func close() {
        guard phase != .running else { return }
        planningGeneration += 1 // Any planning still in flight is now stale.
        phase = .idle
        preview = nil
        isAutomatic = false
    }
}
