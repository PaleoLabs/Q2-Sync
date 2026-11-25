//
//  UpdateWindow.swift
//  Q2-Sync › App
//
//  PURPOSE
//  The small window that answers a check for new versions. It appears over
//  the main window (or in the middle of the screen without one), floats
//  above other windows, including other apps', so it isn't missed, and
//  stays until you close it.
//
//  HOW IT FITS
//  Used by `AppUpdateModel`; its contents are `UpdateNoticeView`. It's an
//  AppKit window, not a SwiftUI scene, because it must be able to appear
//  with no other window open (only views can open a scene). It isn't modal,
//  so it never holds up a sync, quitting or shutting down.
//

import AppKit
import SwiftUI

/// Shows one view in a floating window.
@MainActor
final class UpdateWindow {

    private var window: NSWindow?

    /// Shows the window, or replaces what an open one says.
    ///
    /// - Parameters:
    ///   - view: The window's contents.
    ///   - takeFocus: `true` when you asked for it: Q2 Sync comes forward.
    ///     `false` leaves the keyboard where it is.
    func show(_ view: some View, takeFocus: Bool) {
        let window = self.window ?? makeWindow()
        self.window = window
        let content = NSHostingView(rootView: view)
        window.setContentSize(content.fittingSize)
        window.contentView = content
        // An open one stays where you left it.
        if !window.isVisible { center(window) }
        if takeFocus {
            // See `DockIconController.bringToFront` for why not `activate()`.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else if NSApp.isActive {
            window.makeKeyAndOrderFront(nil)
        }
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    /// Centers the window over the main window, like its sheets, keeping it
    /// on that screen. With no main window showing, centers it on screen.
    private func center(_ window: NSWindow) {
        guard let main = NSApp.windows.first(where: {
            DockIconController.isMainWindow($0) && $0.isVisible && !$0.isMiniaturized
        }) else {
            window.center()
            return
        }
        let size = window.frame.size
        var origin = NSPoint(x: main.frame.midX - size.width / 2, y: main.frame.midY - size.height / 2)
        if let area = main.screen?.visibleFrame {
            origin.x = max(area.minX, min(origin.x, area.maxX - size.width))
            origin.y = max(area.minY, min(origin.y, area.maxY - size.height))
        }
        window.setFrameOrigin(origin)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        window.title = "Q2 Sync Update"
        window.level = .floating
        window.collectionBehavior = .moveToActiveSpace
        window.isRestorable = false
        // We keep it, to show it again.
        window.isReleasedWhenClosed = false
        return window
    }
}
