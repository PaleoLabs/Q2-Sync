//
//  CardVerifyModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Runs "Verify Card" for the UI: reads every song on the card and compares
//  it with the Mac's copy (`CardVerifier`, in the background), then, if you
//  choose, copies damaged or missing songs again through the normal
//  `SyncExecutor` (same safety checks, manifest and log as a sync).
//
//  HOW IT FITS
//  Owned by `AutoSyncController`; drives `VerifyCardSheet`. Syncing and
//  firmware installs wait while it runs, and it won't start during either.
//

import Foundation
import Observation

/// UI state for verifying the card.
@MainActor
@Observable
final class CardVerifyModel {

    enum Phase: Equatable {
        /// Explaining what it does, ready to start.
        case ready
        /// Reading and comparing.
        case checking
        /// Done (or stopped); results in `result`.
        case checked
        /// Copying the failed songs again.
        case repairing
        /// Re-copy finished; results in `repairReport`.
        case repaired
        /// Couldn't start or failed.
        case failed(String)
    }

    var isPresentingSheet = false
    private(set) var phase: Phase = .ready
    private(set) var progress = VerifyProgress()
    private(set) var result: VerifyResult?
    private(set) var repairReport: SyncReport?
    private(set) var secondsRemaining: TimeInterval?

    /// `true` while reading or re-copying.
    var isBusy: Bool { phase == .checking || phase == .repairing }

    private let library: LibraryModel
    private let devices: DeviceMonitor
    private var task: Task<Void, Never>?
    @ObservationIgnored private var estimator = TimeRemainingEstimator()

    init(library: LibraryModel, devices: DeviceMonitor) {
        self.library = library
        self.devices = devices
    }

    /// Opens the sheet.
    func present() {
        if !isBusy { phase = .ready; result = nil; repairReport = nil }
        isPresentingSheet = true
    }

    /// Closes the sheet (not while working).
    func close() {
        guard !isBusy else { return }
        isPresentingSheet = false
    }

    /// Stops the check or re-copy (after the current chunk).
    func cancel() { task?.cancel() }

    /// The library snapshot and card, or why they're not available.
    private func prerequisites() -> (snapshot: LibrarySnapshot, connected: ConnectedDevice, fileSystem: CardFileSystem)? {
        guard let connected = devices.connected, let root = connected.accessURL else {
            phase = .failed("Q2 Sync doesn't have access to the card.")
            return nil
        }
        guard let snapshot = library.snapshot else {
            phase = .failed("Read your library first (the arrow at the top right), so there's something to compare with.")
            return nil
        }
        do {
            let pathGuard = try PathGuard(cardRoot: root, expectedVolumeUUID: connected.device.volumeUUID,
                                          profile: connected.device.profile,
                                          extraProtectedFolders: [snapshot.mediaFolderURL].compactMap { $0 })
            return (snapshot, connected, CardFileSystem(pathGuard: pathGuard))
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Starts reading and comparing.
    func startCheck() {
        guard !isBusy, let ready = prerequisites() else { return }
        let (snapshot, fileSystem) = (ready.snapshot, ready.fileSystem)
        let manifest: SyncManifest
        do { manifest = try SyncManifest.load(from: fileSystem) } catch {
            phase = .failed(error.localizedDescription); return
        }
        phase = .checking
        progress = VerifyProgress()
        secondsRemaining = nil
        estimator = TimeRemainingEstimator()
        let tracks = Dictionary(snapshot.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let report = progressReporter()
        task = Task {
            let found = await Self.check(manifest: manifest, tracks: tracks, fileSystem: fileSystem, report: report)
            result = found
            phase = .checked
            task = nil
        }
    }

    /// Copies the failed songs again.
    func repair() {
        guard !isBusy, let problems = result?.problems, !problems.isEmpty,
              let ready = prerequisites() else { return }
        let (snapshot, connected, fileSystem) = (ready.snapshot, ready.connected, ready.fileSystem)
        let manifest: SyncManifest
        do { manifest = try SyncManifest.load(from: fileSystem) } catch {
            phase = .failed(error.localizedDescription); return
        }
        let tracks = Dictionary(snapshot.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let plan = CardVerifier.repairPlan(for: problems, tracks: tracks)
        let executor = SyncExecutor(fileSystem: fileSystem, deviceName: connected.device.name)
        phase = .repairing
        secondsRemaining = nil
        estimator = TimeRemainingEstimator()
        progress = VerifyProgress(totalBytes: plan.bytesToCopy, totalSongs: plan.copies.count)
        let reportProgress: @Sendable (SyncProgress) -> Void = { [weak self] update in
            Task { @MainActor in
                guard let self else { return }
                self.progress = VerifyProgress(bytesDone: update.bytesCopied, totalBytes: update.totalBytes,
                                               songsDone: update.completedOperations,
                                               totalSongs: update.totalOperations, current: update.currentItem)
                self.secondsRemaining = self.estimator.update(bytesCopied: update.bytesCopied,
                                                              totalBytes: update.totalBytes,
                                                              at: ProcessInfo.processInfo.systemUptime)
            }
        }
        task = Task {
            repairReport = await executor.run(plan: plan, manifest: manifest, options: SyncOptions(),
                                              onProgress: reportProgress)
            devices.reloadCardInfo()
            phase = .repaired
            task = nil
        }
    }

    /// A thread-safe, throttled progress callback for the check.
    private func progressReporter() -> @Sendable (VerifyProgress) -> Void {
        { [weak self] update in
            Task { @MainActor in
                guard let self, self.phase == .checking else { return }
                self.progress = update
                self.secondsRemaining = self.estimator.update(bytesCopied: update.bytesDone,
                                                              totalBytes: update.totalBytes,
                                                              at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    /// The check itself, on a background thread.
    @concurrent
    private nonisolated static func check(manifest: SyncManifest, tracks: [PersistentID: Track],
                                          fileSystem: CardFileSystem,
                                          report: @escaping @Sendable (VerifyProgress) -> Void) async -> VerifyResult {
        let clock = ContinuousClock()
        var last = clock.now - .seconds(1)
        return CardVerifier.verify(manifest: manifest, tracks: tracks, fileSystem: fileSystem) { progress in
            // At most ~10 updates a second.
            if clock.now - last > .milliseconds(100) || progress.songsDone == progress.totalSongs {
                last = clock.now
                report(progress)
            }
        }
    }
}
