//
//  FirmwareInstaller.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Puts Q2 Pod or Shanling stock firmware on the Q2's card, ready for the
//  Q2 to install, when you ask:
//    1. find the latest version (`FirmwareSources`),
//    2. download it to a temp folder on the Mac (or use a file you chose),
//    3. take `update.tar` out of Shanling's zip,
//    4. check it: really Shanling Q2 firmware, the kind you picked, and
//       GitHub's checksum for Q2 Pod (`FirmwareImage`),
//    5. check there's room on the card (the Q2 unpacks it beside itself),
//    6. copy it to the card root as `update.tar` and check the copy
//       (`CardFileSystem.placeFirmwareUpdate`),
//    7. remember it's waiting, so next time the card connects Q2 Sync asks
//       whether the update finished.
//  The Q2 does the update itself (System Update → TF card update). Q2 Sync
//  never changes the firmware on the device.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`. Drives `FirmwareInstallSheet` and
//  `FirmwareFinishedSheet`. Card writes go through `PathGuard` like every
//  other change.
//

import Foundation
import Observation

/// UI state and work for installing firmware.
@MainActor
@Observable
final class FirmwareInstaller {

    /// What the install sheet shows.
    enum Step: Equatable {
        /// Pick which firmware.
        case choosing
        /// Working; the text says on what, with a fraction when known.
        case working(String, fraction: Double?)
        /// The file is on the card; show the steps for the Q2.
        case placed(FirmwareImageInfo)
        /// Something went wrong; the message says what.
        case failed(String)
    }

    /// Whether we found a download for a firmware.
    enum OfferState: Equatable {
        case loading
        case ready(FirmwareOffer)
        case unavailable(String)
    }

    // MARK: State the UI reads

    /// Whether the install sheet is open.
    var isPresentingSheet = false

    /// Whether the "Did the update finish?" sheet is open.
    var isAskingAboutPending = false

    /// The firmware picked in the sheet.
    var target: FirmwareKind = .q2Pod

    /// Where the install has got to.
    private(set) var step: Step = .choosing

    /// The download found for each firmware.
    private(set) var offers: [FirmwareKind: OfferState] = [:]

    /// `true` while downloading or copying (the sheet can't be closed,
    /// and syncing waits).
    var isBusy: Bool {
        if case .working = step { return true }
        return false
    }

    /// Called after the "Did the update finish?" question is answered, so
    /// the normal "when this Q2 connects" behaviour can carry on.
    @ObservationIgnored var onPendingQuestionAnswered: (() -> Void)?

    // MARK: Private

    private let devices: DeviceMonitor
    private var work: Task<Void, Never>?

    /// Space the Q2's updater needs beyond the file itself: it unpacks the
    /// tar beside itself, so twice the file, plus 64 MB (as Q2 Pod's own
    /// Network update requires).
    static let extraSpace: Int64 = 64 * 1024 * 1024

    init(devices: DeviceMonitor) {
        self.devices = devices
    }

    // MARK: - Opening

    /// Opens the install sheet and looks up the latest versions.
    ///
    /// - Parameter kind: The firmware to pre-select; by default the one the
    ///   Q2 runs now (as saved for it), since updating is more common than
    ///   switching. Switching is one click on the other tab.
    func present(selecting kind: FirmwareKind? = nil) {
        guard !isBusy else { isPresentingSheet = true; return }
        target = kind ?? devices.connected?.device.firmware ?? .q2Pod
        step = .choosing
        isPresentingSheet = true
        Task { await loadOffers() }
    }

    /// Closes the sheet (only when not working).
    func close() {
        guard !isBusy else { return }
        isPresentingSheet = false
        step = .choosing
    }

    /// Goes back to choosing after a failure.
    func startOver() {
        guard !isBusy else { return }
        step = .choosing
        Task { await loadOffers() }
    }

    /// Looks up the latest Q2 Pod release and Shanling's current download.
    func loadOffers() async {
        offers = [.q2Pod: .loading, .stock: .loading]
        async let pod = Self.findQ2Pod()
        async let stock = Self.findStock()
        offers[.q2Pod] = await pod
        offers[.stock] = await stock
    }

    private nonisolated static func findQ2Pod() async -> OfferState {
        do {
            return .ready(try FirmwareSources.q2PodOffer(from: try await FirmwareUpdateChecker.fetchLatest()))
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private nonisolated static func findStock() async -> OfferState {
        do {
            var request = URLRequest(url: FirmwareSources.stockDownloadPage)
            request.setValue("Q2-Sync", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw DownloadError.httpStatus(http.statusCode)
            }
            return .ready(try FirmwareSources.stockOffer(fromShanlingPage: String(decoding: data, as: UTF8.self)))
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: - Installing

    /// Where the firmware comes from.
    private enum Source {
        case offer(FirmwareOffer)
        case file(URL)
    }

    /// Downloads the picked firmware and puts it on the card.
    func installSelected() {
        guard case .ready(let offer)? = offers[target] else { return }
        start(.offer(offer), expecting: target)
    }

    /// Puts a firmware file the user chose (a zip or an `update.tar`) on
    /// the card. It must be the firmware picked in the sheet.
    func install(file: URL) {
        start(.file(file), expecting: target)
    }

    /// Stops a download or copy in progress.
    func cancel() {
        work?.cancel()
    }

    private func start(_ source: Source, expecting kind: FirmwareKind) {
        guard !isBusy, let connected = devices.connected else { return }
        guard let cardRoot = connected.accessURL else {
            step = .failed(connected.accessProblem ?? "Q2 Sync doesn't have access to the card.")
            return
        }
        work = Task {
            do {
                let image = try await run(source, expecting: kind, connected: connected, cardRoot: cardRoot)
                devices.setPendingFirmwareInstall(PendingFirmwareInstall(image: image, placedAt: .now))
                devices.reloadCardInfo()
                step = .placed(image)
            } catch is CancellationError {
                step = .failed("Cancelled. Nothing was put on the card.")
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }

    /// The whole pipeline (see the file header).
    private func run(_ source: Source, expecting kind: FirmwareKind,
                     connected: ConnectedDevice, cardRoot: URL) async throws -> FirmwareImageInfo {
        let workFolder = FileManager.default.temporaryDirectory
            .appending(path: "Q2Sync-Firmware-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        // 1–2. Get the file onto the Mac.
        var file: URL
        var expectedSHA256: String?
        switch source {
        case .offer(let offer):
            expectedSHA256 = offer.expectedSHA256
            file = workFolder.appending(path: offer.packaging == .zip ? "download.zip" : FirmwareImage.fileName)
            step = .working("Downloading \(offer.displayName)…", fraction: 0)
            let progress = progressReporter(title: "Downloading \(offer.displayName)…", total: offer.expectedSize)
            try await FileDownloader.download(offer.downloadURL, to: file) { written, expected in
                progress(written, expected)
            }
        case .file(let chosen):
            file = chosen
        }

        // 3. Take update.tar out of a zip.
        if try Self.isZip(file) {
            step = .working("Unpacking…", fraction: nil)
            let tar = workFolder.appending(path: FirmwareImage.fileName)
            try await Self.extract(zip: file, to: tar)
            file = tar
        }

        // 4. Is it what we think it is?
        step = .working("Checking the firmware…", fraction: nil)
        let image = try FirmwareImage.inspect(file)
        guard image.kind == kind else { throw FirmwareImageError.unexpectedKind(expected: kind, found: image.kind) }
        let checksum = try await Self.checksum(of: file)
        if let expectedSHA256, checksum != expectedSHA256 { throw FirmwareImageError.checksumMismatch }

        // 5–6. Room on the card, then copy and check the copy.
        let pathGuard = try PathGuard(cardRoot: cardRoot, expectedVolumeUUID: connected.device.volumeUUID,
                                      profile: connected.device.profile)
        let fileSystem = CardFileSystem(pathGuard: pathGuard)
        let existing = Int64(fileSystem.firmwareUpdateFileSize() ?? 0)
        let free = VolumeInfo.read(at: cardRoot)?.availableCapacity ?? connected.volume.availableCapacity ?? 0
        let needed = 2 * image.size + Self.extraSpace
        if free + existing < needed {
            let short = (needed - free - existing).formatted(.byteCount(style: .file))
            throw InstallError.notEnoughSpace(short)
        }
        let title = "Copying to “\(connected.device.name)”…"
        step = .working(title, fraction: 0)
        let progress = progressReporter(title: title, total: 2 * image.size) // copy, then read back
        try await Self.place(file, sha256: checksum, on: fileSystem, progress: progress)
        return image
    }

    /// Makes a thread-safe progress callback that updates `step`.
    /// `cumulative` callers pass running totals; chunk callers pass sizes.
    private func progressReporter(title: String, total: Int64?) -> @Sendable (Int64, Int64?) -> Void {
        { [weak self] value, expected in
            let total = expected ?? total
            Task { @MainActor in
                guard let self, case .working = self.step else { return }
                self.step = .working(title, fraction: total.map { min(1, Double(value) / Double(max($0, 1))) })
            }
        }
    }

    // MARK: Background work

    /// `true` if a file starts with a zip signature.
    private nonisolated static func isZip(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    @concurrent
    private nonisolated static func extract(zip: URL, to tar: URL) async throws {
        try ZipExtractor.extract(fileNamed: FirmwareImage.fileName, from: zip, to: tar)
    }

    @concurrent
    private nonisolated static func checksum(of file: URL) async throws -> String {
        try FirmwareImage.sha256(of: file)
    }

    @concurrent
    private nonisolated static func place(_ file: URL, sha256: String, on fileSystem: CardFileSystem,
                                          progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        var done: Int64 = 0
        try fileSystem.placeFirmwareUpdate(from: file, expectedSHA256: sha256) { bytes in
            done += Int64(bytes)
            progress(done, nil)
        }
    }

    // MARK: - After the update

    /// Called when the card connects: asks about firmware placed during an
    /// EARLIER connection (not this one), if any.
    ///
    /// - Returns: `true` if the question is being asked.
    func askAboutPendingIfNeeded(for connected: ConnectedDevice) -> Bool {
        guard let pending = connected.device.pendingFirmwareInstall,
              pending.placedAt < connected.connectedAt else { return false }
        isAskingAboutPending = true
        return true
    }

    /// The size of `update.tar` on the connected card, if any.
    func firmwareFileOnCard() -> UInt64? {
        fileSystemForConnectedCard()?.firmwareUpdateFileSize()
    }

    /// The user's answer to "Did the update finish?".
    enum PendingAnswer {
        /// Yes: switch the Q2 to the new firmware.
        case finished(removeFile: Bool)
        /// Not yet: ask again next time.
        case notYet
        /// Don't install it: remove `update.tar` and forget it.
        case cancelUpdate
    }

    /// Acts on the answer to the question asked on connecting, then lets
    /// the normal connect behaviour (auto-sync) carry on.
    func answerPendingQuestion(_ answer: PendingAnswer) {
        switch answer {
        case .finished(let removeFile): markPendingInstalled(removeFile: removeFile)
        case .notYet: break
        case .cancelUpdate: cancelPending()
        }
        isAskingAboutPending = false
        onPendingQuestionAnswered?()
    }

    /// Switches the Q2 to the pending firmware (from the question or the
    /// Settings tab's "Mark as Installed").
    func markPendingInstalled(removeFile: Bool) {
        devices.completePendingFirmwareInstall()
        if removeFile { removeFirmwareFile() }
    }

    /// Removes the pending `update.tar` from the card and forgets it.
    func cancelPending() {
        removeFirmwareFile()
        devices.setPendingFirmwareInstall(nil)
    }

    /// Removes `update.tar` from the connected card.
    private func removeFirmwareFile() {
        do {
            try fileSystemForConnectedCard()?.removeFirmwareUpdate()
            devices.reloadCardInfo()
        } catch {
            devices.errorMessage = "Couldn't remove update.tar from the card: \(error.localizedDescription)"
        }
    }

    private func fileSystemForConnectedCard() -> CardFileSystem? {
        guard let connected = devices.connected, let root = connected.accessURL,
              let pathGuard = try? PathGuard(cardRoot: root, expectedVolumeUUID: connected.device.volumeUUID,
                                             profile: connected.device.profile) else { return nil }
        return CardFileSystem(pathGuard: pathGuard)
    }
}

/// Problems installing, beyond file and download errors.
enum InstallError: LocalizedError, Equatable {
    case notEnoughSpace(String)

    var errorDescription: String? {
        switch self {
        case .notEnoughSpace(let amount):
            return "The card needs \(amount) more free space. The Q2 unpacks the firmware next to itself, so it needs room for about twice the file. Free up some space and try again."
        }
    }
}
