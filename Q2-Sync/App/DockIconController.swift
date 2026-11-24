//
//  DockIconController.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Hides Q2 Sync's Dock icon while its main window is closed, so the app
//  lives only in the menu bar, and shows it again when the window comes
//  back. The first time you close the window it explains this in a sheet
//  ("Keep in Menu Bar" or "Quit Q2 Sync", with "Don't show again").
//
//  HOW IT FITS
//  Created once by `Q2SyncApp`. It watches AppKit's window notifications
//  for the main window (Settings, the sync sheet and alerts don't count).
//  `AutoSyncController.showMainWindow()` calls `showDockIcon()` before
//  bringing the window back.
//
//  ACTIVATION POLICY (explained)
//  `NSApp.setActivationPolicy(.regular)` is a normal app with a Dock icon;
//  `.accessory` is an app with no Dock icon or app menu that can still show
//  windows and a menu bar item. Switching doesn't stop anything running,
//  so a sync carries on.
//
//  CLOSING THE WINDOW (explained)
//  SwiftUI owns the window's delegate, so to ask before closing we put a
//  small "proxy" delegate in front of it: it answers `windowShouldClose`
//  itself and passes every other delegate call on to SwiftUI's.
//

import AppKit

/// Shows or hides the Dock icon as the main window opens and closes.
@MainActor
final class DockIconController {

    /// UserDefaults key: whether closing the window shows the menu bar tip.
    /// Reset by Settings › "Show Menu Bar Tip Again".
    static let closeNoticeKey = "showMenuBarCloseNotice"

    /// The menu bar item's icon (an SF Symbol), also shown in the notice.
    static let menuBarSymbol = "ipod"

    /// The one instance, created at launch by `Q2SyncApp`.
    static let shared = DockIconController()

    /// Keeps the proxy alive (a window holds its delegate weakly).
    private var proxy: CloseProxy?

    /// Starts watching the main window.
    private init() {
        UserDefaults.standard.register(defaults: [Self.closeNoticeKey: true])
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { self.windowBecameMain(window) }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { self.windowWillClose(window) }
        }
    }

    /// Whether `window` is the main Q2 Sync window. SwiftUI names its
    /// identifier after the scene id (e.g. "main" or "main-AppWindow-1").
    static func isMainWindow(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue.hasPrefix(Q2SyncApp.mainWindowID) == true
    }

    /// Puts the Dock icon back. Call before bringing the main window forward.
    func showDockIcon() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    /// Opens Settings from the menu bar item. An app without a Dock icon
    /// can't reliably bring a window to the front, so Settings would open
    /// out of sight: put the Dock icon back while Settings is open (it goes
    /// again when Settings closes, if the main window is still closed).
    func openSettings(_ open: () -> Void) {
        showDockIcon()
        open()
        bringToFront(where: Self.isSettingsWindow)
    }

    /// Makes Q2 Sync the active app with the matching window in front, from
    /// the menu bar or a notification, even while another app (say Xcode)
    /// is active. Waits a moment first: the Dock icon switch and a newly
    /// created window both land a run-loop pass later, and an activation
    /// requested before that is ignored.
    func bringToFront(where matches: @escaping (NSWindow) -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // `activate(ignoringOtherApps:)` is deprecated, but the newer
            // `activate()` is only a polite request that macOS may refuse
            // when another app is in front.
            NSApp.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first(where: matches) else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// Whether `window` is SwiftUI's Settings window.
    static func isSettingsWindow(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue.contains("Settings") == true
    }

    private func hideDockIcon() {
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func windowBecameMain(_ window: NSWindow?) {
        guard let window, Self.isMainWindow(window) else { return }
        showDockIcon()
        // SwiftUI may create a new window (or delegate) each time it opens.
        if proxy?.window !== window || window.delegate !== proxy {
            proxy = CloseProxy(window: window, owner: self)
        }
    }

    private func windowWillClose(_ window: NSWindow?) {
        if Self.isMainWindow(window) {
            hideDockIcon()
        } else if Self.isSettingsWindow(window),
                  !NSApp.windows.contains(where: { Self.isMainWindow($0) && $0.isVisible }) {
            // Settings was opened from the menu bar with the window closed.
            hideDockIcon()
        }
    }

    /// Whether closing should first show the notice.
    fileprivate var shouldExplainOnClose: Bool {
        UserDefaults.standard.bool(forKey: Self.closeNoticeKey)
    }

    /// Shows the notice as a sheet on `window`, then closes the window or
    /// quits, depending on the answer.
    fileprivate func explainThenClose(_ window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Q2 Sync Is Still in the Menu Bar"
        alert.informativeText = "Q2 Sync keeps running after its window closes, so it notices when your Q2 connects. Open it again, sync or eject from its menu bar icon."
        alert.accessoryView = Self.menuBarIconHint()
        alert.addButton(withTitle: "Keep in Menu Bar")
        alert.addButton(withTitle: "Quit Q2 Sync")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show again"
        alert.beginSheetModal(for: window) { response in
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(false, forKey: Self.closeNoticeKey)
            }
            if response == .alertSecondButtonReturn {
                // Goes through the usual "Quit while syncing?" check.
                NSApp.terminate(nil)
            } else {
                // `close()` (unlike `performClose`) doesn't ask again.
                window.close()
            }
        }
    }

    /// "Look for [icon] in the menu bar…", using the same symbol as the
    /// menu bar item so it matches (and follows light and dark mode).
    private static func menuBarIconHint() -> NSView {
        let before = NSTextField(labelWithString: "Look for")
        let icon = NSImageView(image: NSImage(systemSymbolName: menuBarSymbol,
                                              accessibilityDescription: "Q2 Sync menu bar icon") ?? NSImage())
        icon.contentTintColor = .labelColor
        let after = NSTextField(labelWithString: "near the right of the menu bar.")
        let stack = NSStackView(views: [before, icon, after])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.setFrameSize(stack.fittingSize)
        return stack
    }
}

/// Sits in front of SwiftUI's window delegate: answers `windowShouldClose`
/// and forwards everything else.
private final class CloseProxy: NSObject, NSWindowDelegate {

    weak var window: NSWindow?
    /// SwiftUI's delegate. Held strongly so it can't vanish while we stand
    /// in for it; replaced together with this proxy.
    private let original: NSWindowDelegate?
    private weak var owner: DockIconController?

    @MainActor init(window: NSWindow, owner: DockIconController) {
        self.window = window
        self.original = window.delegate
        self.owner = owner
        super.init()
        window.delegate = self
    }

    @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let owner, owner.shouldExplainOnClose, sender.attachedSheet == nil {
            owner.explainThenClose(sender)
            return false
        }
        return original?.windowShouldClose?(sender) ?? true
    }

    // Forwarding: AppKit asks `responds(to:)` before calling an optional
    // delegate method, then sends it to `forwardingTarget(for:)`.
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : nil
    }
}
