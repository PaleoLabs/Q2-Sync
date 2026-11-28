//
//  AppNavigation.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Where you are in the main window, kept outside the views so the menus can
//  read and change it: the selected sidebar row, the Q2 page's tab, the
//  songs selected in the library browser, and the search or filter field
//  Edit › Find would focus.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`. `RootView` and `DeviceView` show what it
//  says; the commands in `AppCommands.swift` use it.
//

import AppKit
import Observation

/// A search or filter field that Edit › Find can put the cursor in.
enum FilterField: Equatable {
    /// The toolbar's search field in the library or Books browser.
    case library
    /// "Filter" on the Q2's Music tab.
    case musicTab
    /// "Search" on the Q2's Audiobooks tab.
    case audiobooksTab
    /// "Search" on the Q2's Podcasts tab.
    case podcastsTab
    /// The filter above the lists in the sync preview.
    case syncPreview
}

/// A part of the Q2's General tab that a menu item can scroll to.
enum GeneralTabSection: Hashable {
    case firmwareUpdates
    case podData
}

/// The main window's selection, shared by its views and the menu bar.
@MainActor
@Observable
final class AppNavigation {

    /// The selected sidebar row. Starts on "Connect Your Q2" until a Q2
    /// has been set up on this Mac, then on Artists.
    var selection: SidebarItem? {
        didSet {
            // The Q2's page opens on General, like Finder: forget the tab
            // when you leave it.
            if case .device = selection { return }
            deviceTab = .general
            // Edits not applied are thrown away when you leave, like Finder.
            if case .device = oldValue { onLeaveDevicePage?() }
        }
    }

    /// Called when the sidebar leaves the Q2's page. Set by
    /// `AutoSyncController` to throw away unapplied edits.
    @ObservationIgnored var onLeaveDevicePage: (() -> Void)?

    /// Which tab of the Q2's page is showing.
    var deviceTab: DeviceTab = .general

    /// The part of the General tab to scroll into view, set by a menu
    /// item whose result appears there. The tab clears it once there.
    var sectionToReveal: GeneralTabSection?

    /// Files of the songs selected in the library browser, for File › Show
    /// in Finder.
    var selectedSongFiles: [URL] = []

    /// `true` while the main window (or a sheet on it) is the one in use.
    /// `false` while it's closed or the help or Settings window is in front.
    private(set) var isMainWindowFront = false

    /// The filter fields on screen.
    private var filterFields: [FilterField] = []

    /// Goes up each time Find is chosen; the filter field on top watches it.
    private(set) var findRequests = 0

    /// The filter field Edit › Find would focus, if any is on screen. The
    /// sync preview's comes first: it opens over the Music tab.
    var filterField: FilterField? {
        filterFields.contains(.syncPreview) ? .syncPreview : filterFields.first
    }

    /// Creates the state and starts watching which window is in front.
    ///
    /// - Parameter hasKnownDevices: Whether a Q2 has been set up before.
    init(hasKnownDevices: Bool) {
        selection = hasKnownDevices ? .library(.artists) : .connectQ2
        let center = NotificationCenter.default
        // A sheet never becomes the "main" window; its parent stays main.
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                self?.isMainWindowFront = DockIconController.isMainWindow(window)
            }
        }
        center.addObserver(forName: NSWindow.didResignMainNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if DockIconController.isMainWindow(window) { self?.isMainWindowFront = false }
            }
        }
    }

    /// Selects the Q2 when it connects, like Finder, and leaves its page
    /// when it goes.
    ///
    /// - Parameter uuid: The connected card, or `nil` if none is.
    func deviceChanged(to uuid: String?) {
        if let uuid { selection = .device(uuid: uuid) }
        else if case .device = selection { selection = .connectQ2 }
    }

    /// Puts the sidebar right when the window appears: a Q2 may have come
    /// or gone while it was closed. A library row stays selected.
    func reconcile(connected uuid: String?) {
        switch selection {
        case .device(let shown) where shown != uuid: deviceChanged(to: uuid)
        case .connectQ2 where uuid != nil: deviceChanged(to: uuid)
        default: break
        }
    }

    /// A filter field came on screen.
    func filterAppeared(_ field: FilterField) {
        filterDisappeared(field)
        filterFields.append(field)
    }

    /// A filter field left the screen.
    func filterDisappeared(_ field: FilterField) {
        filterFields.removeAll { $0 == field }
    }

    /// Asks the filter field on top to take the cursor.
    func find() {
        findRequests += 1
    }
}
