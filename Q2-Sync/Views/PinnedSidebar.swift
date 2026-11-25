//
//  PinnedSidebar.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  Stops the main window's sidebar from being collapsed. It's the only way
//  to get to your Q2 and the library lists, and hiding it gains little.
//
//  HOW IT FITS
//  `RootView` puts this behind the sidebar. SwiftUI has no setting for it,
//  so it asks the AppKit split view underneath. `RootView` also removes the
//  toolbar's sidebar button, and `Q2SyncApp` adds no menu item for it.
//

import AppKit
import SwiftUI

/// An invisible view that keeps the split view column holding it on screen,
/// so dragging the divider can't hide it.
struct PinnedSidebar: NSViewRepresentable {

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) { view.needsLayout = true }

    /// The AppKit view that finds its own column.
    final class Probe: NSView {

        // Applied at each layout, not once: the split view may not be set up
        // when this view first appears, and SwiftUI owns it afterwards.
        override func layout() {
            super.layout()
            pin()
        }

        /// Finds the split view column around this view, and makes it one
        /// that can't collapse.
        private func pin() {
            var ancestor = superview
            while let view = ancestor {
                if let split = view as? NSSplitView,
                   let controller = split.delegate as? NSSplitViewController,
                   let column = controller.splitViewItems.first(where: {
                       isDescendant(of: $0.viewController.view)
                   }) {
                    // Only on a change, so layout doesn't set off more layout.
                    if column.isCollapsed { column.isCollapsed = false }
                    if column.canCollapse { column.canCollapse = false }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
