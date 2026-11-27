//
//  FirmwareModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Holds the firmware checks for the UI:
//    • Q2 Pod: an optional automatic check (whether it's on, the latest
//      release found, when it last checked, and any error);
//    • Shanling stock: the latest version, checked only when you ask.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`, which checks (at most once a day) when a
//  Q2 Pod device connects, and posts a notification for a new release.
//  The device's General tab shows the details and a "Check Now" button;
//  Device › Check for Firmware Updates checks whichever firmware the Q2
//  runs. The requests live in Core (`FirmwareUpdateChecker`,
//  `FirmwareSources`).
//
//  It only reads release information; `FirmwareInstaller` downloads
//  firmware, and only when you ask.
//

import Foundation
import Observation

/// UI state for firmware update checks.
@MainActor
@Observable
final class FirmwareModel {

    /// UserDefaults keys.
    static let enabledKey = "checkFirmwareUpdates"
    private static let latestKey = "latestFirmwareRelease"
    private static let lastCheckedKey = "lastFirmwareCheck"
    private static let notifiedKey = "notifiedFirmwareRelease"
    private static let latestStockKey = "latestStockFirmwareVersion"

    /// How often automatic checks may run.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// The latest release found (kept between launches).
    private(set) var latest: FirmwareRelease?

    /// When the last successful check happened.
    private(set) var lastChecked: Date?

    /// `true` while a check is running.
    private(set) var isChecking = false

    /// The last check's error, if it failed.
    private(set) var errorMessage: String?

    /// `true` once Check for Firmware Updates was chosen from the menu, so
    /// the result shows even with automatic checking off.
    private(set) var wasCheckedOnRequest = false

    /// The latest Shanling stock version found, e.g. "1.36" (kept between
    /// launches).
    private(set) var latestStockVersion: String?

    /// `true` while checking Shanling's page.
    private(set) var isCheckingStock = false

    /// The last stock check's error, if it failed.
    private(set) var stockErrorMessage: String?

    private let defaults = UserDefaults.standard

    /// Whether checking is turned on (off until the user turns it on).
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    init() {
        if let data = defaults.data(forKey: Self.latestKey) {
            latest = try? JSONDecoder().decode(FirmwareRelease.self, from: data)
        }
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        latestStockVersion = defaults.string(forKey: Self.latestStockKey)
    }

    /// Checks if checking is on and the last check was over a day ago.
    func checkIfDue() async {
        guard isEnabled else { return }
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.checkInterval { return }
        await checkNow()
    }

    /// `true` while the check for this firmware is running.
    func isChecking(_ kind: FirmwareKind) -> Bool {
        kind == .q2Pod ? isChecking : isCheckingStock
    }

    /// Device › Check for Firmware Updates: checks the firmware the Q2 runs.
    func checkOnRequest(for kind: FirmwareKind) async {
        switch kind {
        case .q2Pod: await checkOnRequest()
        case .stock: await checkStockNow()
        }
    }

    /// Looks up the latest stock version on Shanling's page.
    func checkStockNow() async {
        guard !isCheckingStock else { return }
        isCheckingStock = true
        defer { isCheckingStock = false }
        do {
            latestStockVersion = try await FirmwareSources.fetchStockOffer().version
            stockErrorMessage = nil
            defaults.set(latestStockVersion, forKey: Self.latestStockKey)
        } catch {
            stockErrorMessage = "Couldn't check for updates: \(error.localizedDescription)"
        }
    }

    /// Checks right away because the user asked from the menu.
    private func checkOnRequest() async {
        wasCheckedOnRequest = true
        await checkNow()
    }

    /// Checks GitHub right away.
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await FirmwareUpdateChecker.fetchLatest()
            latest = release
            lastChecked = .now
            errorMessage = nil
            defaults.set(try? JSONEncoder().encode(release), forKey: Self.latestKey)
            defaults.set(lastChecked, forKey: Self.lastCheckedKey)
        } catch {
            errorMessage = "Couldn't check for updates: \(error.localizedDescription)"
        }
    }

    /// The status for a device, or `nil` if nothing has been checked yet.
    func status(for device: KnownDevice) -> FirmwareUpdateStatus? {
        guard device.firmware == .q2Pod, let latest else { return nil }
        return FirmwareUpdateChecker.status(latest: latest, installed: device.installedFirmwareVersion,
                                            dismissedTag: device.dismissedFirmwareRelease)
    }

    /// `true` the first time a given release is worth a notification, so
    /// each release is announced only once.
    func shouldAnnounce(_ release: FirmwareRelease) -> Bool {
        guard defaults.string(forKey: Self.notifiedKey) != release.tag else { return false }
        defaults.set(release.tag, forKey: Self.notifiedKey)
        return true
    }
}
