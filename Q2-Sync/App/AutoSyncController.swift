//
//  AutoSyncController.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Connects the pieces that make Q2 Sync work in the background:
//    • when your Q2 connects, it asks (notification) or syncs straight
//      away, depending on that card's "When This Q2 Connects" setting;
//    • it turns automatic syncs' outcomes into notifications;
//    • it handles the notification buttons (Sync Now, Eject, Verify Card,
//      Open);
//    • it tells you about a new Q2 that needs setting up when the window
//      isn't in front.
//  Connect notifications are only posted while Q2 Sync isn't in front
//  (when it is, you're already looking at the Q2), and notification
//  permission is only asked for when one is actually posted.
//
//  SAFETY
//  Automatic syncs go through exactly the same engine and checks as
//  manual ones. `SyncCoordinator` consults `AutoSyncPolicy`, which stops
//  and leaves the preview open whenever anything needs your review (first
//  sync, failed checks, removals, songs gone from your library). Auto-sync
//  never removes anything, and never ejects: the "finished" notification
//  offers an Eject button instead.
//

import AppKit
import Observation

/// Coordinates auto-sync, notifications and the menu bar.
@MainActor
@Observable
final class AutoSyncController {

    let library: LibraryModel
    let devices: DeviceMonitor
    let sync: SyncCoordinator

    /// Posts notifications and reports their buttons.
    @ObservationIgnored let notifications = NotificationManager()

    /// Optional Q2 Pod firmware update checks.
    let firmware = FirmwareModel()

    /// Puts firmware on the card when you ask, and asks afterwards whether
    /// the Q2 installed it.
    let installer: FirmwareInstaller

    /// "Verify Card": compares the card's songs with the Mac's.
    let verifier: CardVerifyModel

    /// Backs up and restores Q2 Pod's own data on the card.
    let podData: PodDataModel

    /// Opens (or brings forward) the main window. Set by a view that has
    /// SwiftUI's `openWindow` action, since only views can get it.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    /// Creates the controller and starts watching for the Q2.
    init(library: LibraryModel, devices: DeviceMonitor, sync: SyncCoordinator) {
        self.library = library
        self.devices = devices
        self.sync = sync
        self.installer = FirmwareInstaller(devices: devices)
        self.verifier = CardVerifyModel(library: library, devices: devices)
        self.podData = PodDataModel(devices: devices)

        notifications.configure()
        // `[weak self]` avoids a retain cycle: these closures are stored by
        // objects this controller owns references to.
        devices.onDeviceConnected = { [weak self] connected in self?.deviceConnected(connected) }
        devices.onNewDriveNeedsSetUp = { [weak self] volume in self?.newDriveNeedsSetUp(volume) }
        sync.onAutomaticEvent = { [weak self] event in self?.handle(event) }
        notifications.onAction = { [weak self] action in self?.handle(action) }
        installer.onPendingQuestionAnswered = { [weak self] in
            guard let self, let connected = self.devices.connected else { return }
            self.runConnectBehaviour(connected)
        }
        // Start watching drives once the app is running. This init runs
        // while SwiftUI builds the app, before `NSApp` exists; a Q2 already
        // plugged in would connect right away and could need the window
        // (e.g. "Did the firmware update finish?"). The main queue runs
        // this after launch.
        DispatchQueue.main.async { devices.start() }
    }

    // MARK: - Connecting

    /// The Q2 connected: first ask about firmware put on the card last
    /// time, if any; then do what its setting says.
    private func deviceConnected(_ connected: ConnectedDevice) {
        if installer.askAboutPendingIfNeeded(for: connected) {
            // Auto-sync waits for the answer (it may change the firmware).
            Task {
                await notifications.requestPermission()
                notifications.postFirmware(title: "Did the Firmware Update Finish?",
                                           body: "Open Q2 Sync to tell it which firmware your Q2 runs now.")
            }
            showMainWindow()
            return
        }
        runConnectBehaviour(connected)
    }

    /// Firmware check plus the "When this Q2 connects" setting.
    private func runConnectBehaviour(_ connected: ConnectedDevice) {
        Task { await checkFirmware(for: connected.device) }
        let mode = connected.device.effectiveAutoSync
        // Read (or refresh) the Music library now, so the device page is
        // ready to choose from. An automatic sync reads it itself. Not
        // before the first-launch notice has been accepted.
        if mode != .automatic,
           UserDefaults.standard.bool(forKey: FirstLaunchNoticeView.acknowledgedKey) {
            Task { await library.load() }
        }
        switch mode {
        case .off:
            break
        case .ask:
            // Only when Q2 Sync isn't in front: otherwise the Q2's page is
            // already showing, with its Sync button.
            postIfInBackground { $0.postConnected(deviceName: connected.device.name) }
        case .automatic:
            Task {
                await notifications.requestPermission()
                await startSync(automatic: true)
            }
        }
    }

    /// A new drive that looks like a Q2 is waiting for setup. If the window
    /// isn't in front, say so; the notification opens it to the sheet.
    private func newDriveNeedsSetUp(_ volume: VolumeInfo) {
        postIfInBackground { $0.postNewDevice(name: volume.name) }
    }

    // MARK: - In front or not

    /// `true` if Q2 Sync is the active app with its main window showing.
    var isInFront: Bool {
        NSApp.isActive && NSApp.windows.contains {
            $0.identifier?.rawValue.hasPrefix(Q2SyncApp.mainWindowID) == true && $0.isVisible && !$0.isMiniaturized
        }
    }

    /// Posts a notification only if Q2 Sync isn't in front, asking for
    /// permission first (macOS asks the user once). Waits a moment so that,
    /// at launch, the window has had time to open before deciding.
    private func postIfInBackground(_ post: @escaping (NotificationManager) -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !isInFront else { return }
            await notifications.requestPermission()
            post(notifications)
        }
    }

    // MARK: - Card busy state

    /// The things that can use the card.
    enum CardTool { case sync, installer, verifier, podData }

    /// `true` while something other than `tool` is using the card (or a
    /// sync sheet is open), so `tool` must not start. Every Sync, Install,
    /// Verify and Back Up / Restore button uses this, so they agree.
    func isCardInUse(except tool: CardTool? = nil) -> Bool {
        (tool != .sync && sync.phase != .idle)
            || (tool != .installer && installer.isBusy)
            || (tool != .verifier && verifier.isBusy)
            || (tool != .podData && podData.isBusy)
    }

    /// `true` while anything is reading or writing the card, so it must
    /// not be ejected. (An open preview or result sheet doesn't count: a
    /// stale preview can't be applied to an ejected card.)
    var isCardBusy: Bool {
        sync.isUsingCard || installer.isBusy || verifier.isBusy || podData.isBusy
    }

    /// What's using the card, in words for the Quit warning, or `nil`.
    var cardBusyActivity: String? {
        if sync.phase == .running { return "A sync is in progress" }
        if installer.isBusy { return "Firmware is being put on the card" }
        if verifier.isBusy { return "Verify Card is running" }
        if podData.isBusy { return "Q2 Pod data is being backed up or restored" }
        return nil
    }

    /// `true` if a new card operation (sync, install, verify) can start.
    var canStartCardOperation: Bool {
        devices.connected?.accessURL != nil && !isCardInUse()
    }

    /// Ejects the card, unless something is still using it. Every Eject
    /// button and notification action goes through here.
    ///
    /// - Returns: `true` if the card was ejected.
    @discardableResult
    func eject() async -> Bool {
        guard !isCardBusy else {
            devices.errorMessage = "Q2 Sync is still using the card. Wait for it to finish, then eject."
            return false
        }
        return await devices.eject()
    }

    /// Starts a sync of the connected Q2.
    ///
    /// - Parameter automatic: `true` applies it without the preview when
    ///   `AutoSyncPolicy` allows; `false` shows the preview as usual.
    func startSync(automatic: Bool) async {
        guard let connected = devices.connected, !isCardInUse() else { return }
        if !automatic { showMainWindow() }
        await sync.prepare(connected: connected, library: library, devices: devices, automatic: automatic)
    }

    /// Checks for Q2 Pod updates (if turned on, at most daily) and announces
    /// a new release once.
    private func checkFirmware(for device: KnownDevice) async {
        guard device.firmware == .q2Pod, firmware.isEnabled else { return }
        await firmware.checkIfDue()
        guard let latest = firmware.latest, firmware.status(for: device)?.shouldNotify == true,
              firmware.shouldAnnounce(latest) else { return }
        await notifications.requestPermission()
        notifications.postFirmware(title: "Q2 Pod \(latest.tag) Is Available",
                                   body: "See what's new, and put it on your Q2's card, in Q2 Sync › your Q2 › Settings.")
    }

    // MARK: - Outcomes

    private func handle(_ event: SyncCoordinator.AutomaticEvent) {
        let name = devices.connected?.device.name ?? "Your Q2"
        switch event {
        case .upToDate:
            notifications.postFinished(title: "“\(name)” Is Up to Date",
                                       body: "Nothing needed syncing.", offerEject: true)
        case .needsReview(let reasons):
            notifications.postNeedsReview(reasons: reasons)
            showMainWindow()
        case .finished(let report):
            if report.succeeded {
                var body = "Added \(report.added), updated \(report.updated)."
                let cardOnly = sync.preview?.plan.cardOnly.count ?? 0
                if cardOnly > 0 {
                    body += " \(pluralized(cardOnly, "file")) on the card \(cardOnly == 1 ? "isn't" : "aren't") in your library; open Q2 Sync to review \(cardOnly == 1 ? "it" : "them")."
                }
                notifications.postFinished(title: "Sync Complete", body: body, offerEject: true)
            } else {
                let reason = report.abortReason ?? (report.wasCancelled ? "It was cancelled."
                                                    : "\(pluralized(report.errors.count, "song")) had problems.")
                notifications.postFinished(title: "Sync Stopped", body: reason + " The card is still connected.",
                                           offerEject: false)
            }
        case .failed(let message):
            notifications.postFinished(title: "Sync Stopped", body: message, offerEject: false)
        }
    }

    private func handle(_ action: NotificationAction) {
        switch action {
        case .syncNow:
            // From "Q2 connected — sync now?": same safety rules as auto-sync.
            Task { await startSync(automatic: true) }
        case .eject:
            // The notification may be old; never eject mid-operation.
            Task { await eject() }
        case .open:
            showMainWindow()
        case .verify:
            // From "Sync Complete": the same Verify Card as in the window.
            showMainWindow()
            // The finished sync's result sheet would block it: close it.
            if sync.phase == .finished { sync.close() }
            guard devices.connected?.accessURL != nil, !isCardInUse(except: .verifier) else { return }
            verifier.present()
        }
    }

    /// Brings the app and its main window to the front: an open (or
    /// minimised) window is brought forward; a closed one is reopened.
    func showMainWindow() {
        // `NSApp` is nil until the app has launched; try again then (the
        // window opens at launch anyway).
        guard NSApp != nil else {
            DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
            return
        }
        // From the menu bar, the app may not be the active app yet.
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI names the window's identifier after the scene id
        // (e.g. "main" or "main-AppWindow-1").
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix(Q2SyncApp.mainWindowID) == true
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
}
