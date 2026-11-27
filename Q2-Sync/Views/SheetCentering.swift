//
//  SheetCentering.swift
//  Q2-Sync
//
//  Keeps a sheet centred in the window it hangs from when its size changes.
//  macOS centres a sheet when it opens, but when SwiftUI later grows it
//  (Show Details) the sheet keeps its top edge and grows downward, so it
//  ends up low in the window. This re-centres it after every resize.
//

import AppKit
import SwiftUI

extension View {
    /// Re-centres the sheet this view is in on its parent window whenever
    /// the sheet changes size.
    func keepsSheetCentered() -> some View {
        background(SheetCenteringView())
    }
}

private struct SheetCenteringView: NSViewRepresentable {
    func makeNSView(context: Context) -> CenteringView { CenteringView() }
    func updateNSView(_ nsView: CenteringView, context: Context) {}

    final class CenteringView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Called with a nil window when the sheet closes: stop observing.
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    Self.center(window)
                }
            }
        }

        /// Puts the sheet's centre on its parent's centre (vertically and
        /// horizontally), keeping it on screen.
        @MainActor
        private static func center(_ sheet: NSWindow) {
            guard let parent = sheet.sheetParent else { return }
            let p = parent.frame
            var origin = NSPoint(x: p.midX - sheet.frame.width / 2,
                                 y: p.midY - sheet.frame.height / 2)
            if let visible = (parent.screen ?? NSScreen.main)?.visibleFrame {
                origin.y = min(max(origin.y, visible.minY), visible.maxY - sheet.frame.height)
            }
            origin.x = origin.x.rounded()
            origin.y = origin.y.rounded()
            if origin != sheet.frame.origin { sheet.setFrameOrigin(origin) }
        }
    }
}
