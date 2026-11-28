//
//  NotificationManager.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Shows macOS notifications ("Q2 connected — sync now?", "Sync complete",
//  "Sync needs your review", "Ejected" or "Wasn't ejected") and handles
//  their buttons (Sync Now, Eject).
//
//  HOW IT FITS
//  `AutoSyncController` asks this to post notifications, and gets a
//  callback when you click a button. It uses Apple's UserNotifications
//  framework (`UNUserNotificationCenter`).
//
//  SWIFT NOTE
//  The notification center calls its delegate methods on a background
//  thread, so they're marked `nonisolated` and hop to the main actor
//  (`Task { @MainActor in … }`) before touching app state.
//

import Foundation
import UserNotifications

/// Buttons a notification can show.
enum NotificationAction: String {
    case syncNow = "SYNC_NOW"
    case eject = "EJECT"
    case open = "OPEN"
    case verify = "VERIFY"
}

/// Posts notifications and reports button clicks.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    /// Called on the main actor when the user clicks a notification or one
    /// of its buttons.
    var onAction: ((NotificationAction) -> Void)?

    private let center = UNUserNotificationCenter.current()

    /// Category identifiers (which set of buttons a notification shows).
    private enum Category {
        static let connected = "Q2_CONNECTED"
        static let finished = "SYNC_FINISHED"
        /// A finished sync that left something to look at in the window.
        static let finishedReview = "SYNC_FINISHED_REVIEW"
        static let review = "SYNC_REVIEW"
    }

    /// Registers the button sets and becomes the delegate.
    func configure() {
        center.delegate = self
        let sync = UNNotificationAction(identifier: NotificationAction.syncNow.rawValue, title: "Sync Now")
        let eject = UNNotificationAction(identifier: NotificationAction.eject.rawValue, title: "Eject")
        // Verify needs the window (it shows progress and results there).
        let verify = UNNotificationAction(identifier: NotificationAction.verify.rawValue, title: "Verify Card",
                                          options: [.foreground])
        let open = UNNotificationAction(identifier: NotificationAction.open.rawValue, title: "Open Q2 Sync",
                                        options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.connected, actions: [sync], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.finished, actions: [eject, verify], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.finishedReview, actions: [open, eject, verify],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.review, actions: [open], intentIdentifiers: []),
        ])
    }

    /// Asks macOS for permission to show notifications (once; macOS
    /// remembers the answer).
    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// `true` if a notification would actually appear on screen: allowed
    /// for Q2 Sync, with a banner or persistent style (not None) in
    /// System Settings › Notifications.
    func canShowAlerts() async -> Bool {
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        return allowed && settings.alertSetting == .enabled && settings.alertStyle != .none
    }

    // MARK: - Posting

    /// "Your Q2 is connected. Sync now?"
    func postConnected(deviceName: String) {
        post(title: "“\(deviceName)” Connected", body: "Sync it with your music now?",
             category: Category.connected, id: "connected")
    }

    /// A finished (or failed) automatic sync.
    ///
    /// - Parameter offerOpen: Adds an Open Q2 Sync button, for a sync that
    ///   left something to review (files on the card not in your library).
    func postFinished(title: String, body: String, offerEject: Bool, offerOpen: Bool = false) {
        let category = !offerEject ? Category.review : offerOpen ? Category.finishedReview : Category.finished
        post(title: title, body: body, category: category, id: "finished")
    }

    /// An eject worked while the main window wasn't there to show it.
    func postEjected(deviceName: String, message: String) {
        post(title: "“\(deviceName)” Ejected", body: message,
             category: Category.review, id: "eject")
    }

    /// An eject failed while the main window couldn't show why.
    func postEjectFailed(deviceName: String, message: String) {
        post(title: "“\(deviceName)” Wasn't Ejected", body: message,
             category: Category.review, id: "eject")
    }

    /// A drive that looks like a Q2 needs setting up.
    func postNewDevice(name: String) {
        post(title: "Set Up Your Q2?", body: "“\(name)” connected. Open Q2 Sync to set it up.",
             category: Category.review, id: "newDevice")
    }

    /// A new firmware release is available.
    func postFirmware(title: String, body: String) {
        post(title: title, body: body, category: Category.review, id: "firmware")
    }

    /// An automatic sync stopped and is waiting for review.
    func postNeedsReview(reasons: [String]) {
        post(title: "Sync Needs Your Review", body: reasons.joined(separator: " "),
             category: Category.review, id: "review")
    }

    private func post(title: String, body: String, category: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        // Reusing the identifier replaces an older notification of the same kind.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - Delegate

    /// Show notifications even while the app is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// A notification or one of its buttons was clicked.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let identifier = response.actionIdentifier
        await MainActor.run {
            if let action = NotificationAction(rawValue: identifier) {
                onAction?(action)
            } else if identifier == UNNotificationDefaultActionIdentifier {
                // Clicking the notification itself just opens the app; only
                // the explicit "Sync Now" button starts a sync.
                onAction?(.open)
            }
        }
    }
}
