//
//  AppUpdateModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Tells you when a newer release of Q2 Sync is on GitHub:
//    • automatically at launch, then once a day while it runs (it often
//      stays in the menu bar for weeks), unless turned off in Settings;
//    • when you choose Check for Updates… (app menu or menu bar item),
//      which always answers.
//  Either way the answer is a small window (`UpdateNoticeView`). A new
//  version keeps being offered until you update or choose Skip This
//  Version. An automatic find waits its turn: it doesn't appear on top of
//  a sync, a question or a permission prompt.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`. The menu bar item also offers the new
//  version for as long as it's available. The request lives in Core
//  (`AppUpdateChecker`), the window in `UpdateWindow`.
//
//  It never downloads or installs anything: it opens the release's web page.
//

import Foundation
import Observation

/// Checks for new releases of Q2 Sync.
@MainActor
@Observable
final class AppUpdateModel {

    /// UserDefaults key: whether to check without being asked (on unless
    /// turned off in Settings).
    static let automaticKey = "checkForAppUpdates"
    private static let skippedKey = "skippedAppRelease"

    /// Time between automatic checks.
    private static let checkInterval: Duration = .seconds(24 * 60 * 60)

    /// Time before trying again after an automatic check failed, e.g. when
    /// the network isn't up yet just after login.
    private static let retryInterval: Duration = .seconds(60 * 60)

    /// How long an automatic find is held after the check, to let whatever
    /// launching sets off (reading the library, an automatic sync) begin.
    private static let settleDelay: Duration = .seconds(5)

    /// A release newer than this app, if the last successful check found one.
    private(set) var available: AppRelease?

    /// `true` while Check for Updates… is waiting for GitHub.
    private(set) var isCheckingOnRequest = false

    @ObservationIgnored private let window = UpdateWindow()

    /// Counts checks you asked for, which answer by themselves.
    private var requestCount = 0

    private let defaults = UserDefaults.standard

    /// This app's version (MARKETING_VERSION), e.g. "0.2".
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var checksAutomatically: Bool {
        defaults.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    /// Checks now and then daily, for as long as the app runs, and shows the
    /// window for a newer release you haven't skipped.
    ///
    /// - Parameter isBusy: `true` while something else has your attention;
    ///   the window waits until it's `false`.
    func startAutomaticChecks(waitingWhile isBusy: @escaping () -> Bool) {
        Task { [weak self] in
            while !Task.isCancelled {
                var failed = false
                if let self, self.checksAutomatically {
                    do {
                        if let release = try await self.check(),
                           self.defaults.string(forKey: Self.skippedKey) != release.tag {
                            await self.offerWhenQuiet(release, isBusy: isBusy)
                        }
                    } catch {
                        // Quiet: you didn't ask, and it will try again.
                        failed = true
                    }
                }
                try? await Task.sleep(for: failed ? Self.retryInterval : Self.checkInterval)
            }
        }
    }

    /// Check for Updates…: checks right away and says what it found, even
    /// for a skipped version.
    func checkOnRequest() async {
        guard !isCheckingOnRequest else { return }
        isCheckingOnRequest = true
        requestCount += 1
        defer { isCheckingOnRequest = false }
        do {
            if let release = try await check() {
                show(.available(release), takeFocus: true)
            } else {
                show(.upToDate, takeFocus: true)
            }
        } catch {
            show(.failed(error.localizedDescription), takeFocus: true)
        }
    }

    /// Shows an automatic find once nothing else is going on. Not if you
    /// checked yourself in the meantime: you've had your answer.
    private func offerWhenQuiet(_ release: AppRelease, isBusy: () -> Bool) async {
        let requestsBefore = requestCount
        try? await Task.sleep(for: Self.settleDelay)
        // Quiet twice in a row, a second apart, so it doesn't slip in
        // between one step and the next.
        var quietChecks = 0
        while quietChecks < 2, !Task.isCancelled {
            quietChecks = isBusy() ? 0 : quietChecks + 1
            try? await Task.sleep(for: .seconds(1))
        }
        guard requestCount == requestsBefore, checksAutomatically else { return }
        // Without taking over the keyboard: you may be typing in another app.
        show(.available(release), takeFocus: false)
    }

    /// Asks GitHub for the latest release and remembers it if it's newer.
    ///
    /// - Returns: The newer release, or `nil` if this app is current.
    private func check() async throws -> AppRelease? {
        let latest = try await AppUpdateChecker.fetchLatest()
        available = latest.isNewer(than: currentVersion) ? latest : nil
        return available
    }

    private func show(_ notice: UpdateNotice, takeFocus: Bool) {
        let view = UpdateNoticeView(
            notice: notice,
            currentVersion: currentVersion,
            download: { [weak self] in
                SupportActions.showLatestRelease()
                self?.window.close()
            },
            skip: { [weak self] release in
                self?.defaults.set(release.tag, forKey: Self.skippedKey)
                self?.window.close()
            },
            close: { [weak self] in self?.window.close() })
        window.show(view, takeFocus: takeFocus)
    }
}
