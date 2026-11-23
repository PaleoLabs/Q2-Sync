//
//  TrackTableView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  A sortable, Finder-style table of songs: number, title, artist, album,
//  time, where each song stands with the Q2 (including why it can't be
//  synced), and an optional File column, hidden by default (right-click
//  the header to show or hide columns). The file path on your Mac is in
//  each title's tooltip and the right-click menu (Show in Finder, Copy
//  Path).
//
//  HOW IT FITS
//  Shown on the right of `LibraryCategoryView`. An `NSTableView` wrapped
//  for SwiftUI (see `AppKitTableSupport.swift` for why AppKit): it
//  reuses a screenful of plain cells however many songs there are.
//  Column widths, order and visibility are saved by AppKit
//  ("TrackTable" autosave).
//

import AppKit
import SwiftUI

/// A table of songs.
struct TrackTableView: NSViewRepresentable {

    /// The songs to show, in their natural (album/playlist) order.
    let tracks: [Track]

    /// Q2 marks for the songs, or `nil` while they're being worked out.
    var marks: LibraryMarks? = nil

    /// Called with the selected songs whenever the selection changes (for
    /// the song inspector).
    var onSelect: ([Track]) -> Void = { _ in }

    /// Called by the right-click menu's "Show Info".
    var onShowInfo: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = 22

        for spec in Coordinator.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = spec.minWidth
            if let maxWidth = spec.maxWidth { column.maxWidth = maxWidth }
            column.isHidden = spec.hiddenByDefault
            if let key = spec.sortKey {
                column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            }
            if spec.id == "time" || spec.id == "number" { column.headerCell.alignment = .right }
            tableView.addTableColumn(column)
        }
        // Saves widths, order and hidden columns across launches.
        tableView.autosaveName = "TrackTable"
        tableView.autosaveTableColumns = true

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView

        let rowMenu = NSMenu()
        rowMenu.delegate = context.coordinator
        tableView.menu = rowMenu
        let headerMenu = NSMenu()
        headerMenu.delegate = context.coordinator
        tableView.headerView?.menu = headerMenu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onShowInfo = onShowInfo
        context.coordinator.update(tracks: tracks, marks: marks)
    }

    // MARK: - Coordinator

    /// Data source, delegate and menus.
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

        struct ColumnSpec {
            let id: String
            let title: String
            let width: CGFloat
            let minWidth: CGFloat
            var maxWidth: CGFloat? = nil
            var sortKey: String? = nil
            var hiddenByDefault = false
        }

        /// The columns, in their default order. Clicking "#" sorts back to
        /// the natural (album or playlist) order.
        static let columns: [ColumnSpec] = [
            ColumnSpec(id: "number", title: "#", width: 28, minWidth: 24, maxWidth: 60, sortKey: "position"),
            ColumnSpec(id: "title", title: "Title", width: 220, minWidth: 80, sortKey: "title"),
            ColumnSpec(id: "artist", title: "Artist", width: 160, minWidth: 60, sortKey: "artist"),
            ColumnSpec(id: "album", title: "Album", width: 180, minWidth: 60, sortKey: "album"),
            ColumnSpec(id: "time", title: "Time", width: 50, minWidth: 40, maxWidth: 80, sortKey: "time"),
            ColumnSpec(id: "q2", title: "On Q2", width: 44, minWidth: 36, maxWidth: 60),
            ColumnSpec(id: "file", title: "File", width: 300, minWidth: 80, hiddenByDefault: true),
        ]

        weak var tableView: NSTableView?
        var onSelect: ([Track]) -> Void = { _ in }
        var onShowInfo: (() -> Void)?

        /// The songs in natural order, their marks, and the order shown
        /// (indexes into `tracks`, after sorting).
        private var tracks: [Track] = []
        private var trackIDs: [PersistentID] = []
        private var placements: [TrackPlacement?] = []
        private var order: [Int] = []

        /// `true` while applying an update from SwiftUI: selection changes
        /// then aren't reported back (that would change SwiftUI state in
        /// the middle of its own update; the parent clears its selection
        /// itself when the list changes).
        private var isUpdating = false

        /// Takes new songs or marks from SwiftUI. A different list reloads
        /// and clears the selection; changed marks or tags only redraw.
        func update(tracks newTracks: [Track], marks: LibraryMarks?) {
            guard let tableView else { return }
            isUpdating = true
            defer { isUpdating = false }
            let newIDs = newTracks.map(\.id)
            let newPlacements = newTracks.map { marks?.placement(of: $0.id) }
            if newIDs != trackIDs {
                tracks = newTracks
                trackIDs = newIDs
                placements = newPlacements
                sortRows()
                tableView.reloadData()
                tableView.deselectAll(nil)
                if !order.isEmpty { tableView.scrollRowToVisible(0) }
            } else if newPlacements != placements || newTracks != tracks {
                tracks = newTracks
                placements = newPlacements
                // Redraw rows in place: `reloadData` would drop the selection.
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<order.count),
                                     columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            }
        }

        /// Applies the table's sort (or the natural order) to `order`.
        private func sortRows() {
            order = Array(tracks.indices)
            guard let descriptor = tableView?.sortDescriptors.first, let key = descriptor.key,
                  key != "position" || !descriptor.ascending else { return }
            let ascending = descriptor.ascending
            let tracks = tracks
            order.sort { i, j in
                let a = tracks[i], b = tracks[j]
                let result: ComparisonResult
                switch key {
                case "title":  result = a.title.localizedStandardCompare(b.title)
                case "artist": result = SortKey.order(a.displayArtist, b.displayArtist)
                case "album":  result = SortKey.order(a.displayAlbum, b.displayAlbum)
                case "time":   result = a.durationSeconds < b.durationSeconds ? .orderedAscending
                                   : a.durationSeconds > b.durationSeconds ? .orderedDescending : .orderedSame
                default:       result = .orderedSame // "position": natural order, reversed below.
                }
                if result == .orderedSame { return ascending ? i < j : i > j }
                return (result == .orderedAscending) == ascending
            }
        }

        // MARK: Data source and delegate

        func numberOfRows(in tableView: NSTableView) -> Int { order.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let id = tableColumn?.identifier.rawValue, order.indices.contains(row) else { return nil }
            let index = order[row]
            let track = tracks[index]
            let path = track.fileURL?.path
            switch id {
            case "number":
                return TableCells.text(tableView, id: id, track.trackNumber > 0 ? "\(track.trackNumber)" : "",
                                       secondary: true, monospacedDigits: true, alignment: .right)
            case "title":
                return TableCells.text(tableView, id: id, track.title, toolTip: path ?? "No file on this Mac")
            case "artist":
                return TableCells.text(tableView, id: id, track.displayArtist)
            case "album":
                return TableCells.text(tableView, id: id, track.displayAlbum)
            case "time":
                return TableCells.text(tableView, id: id,
                                       Duration.seconds(track.durationSeconds).formatted(.time(pattern: .minuteSecond)),
                                       monospacedDigits: true, alignment: .right)
            case "q2":
                let placement = placements[index]
                return TableCells.icons(tableView, id: id, [TableIcon.song(track, placement: placement)],
                                        placeholder: track.isCopyable && placement == .notChosen)
            case "file":
                return TableCells.text(tableView, id: id, path ?? "—", secondary: true,
                                       truncation: .byTruncatingHead, toolTip: path ?? "No file on this Mac")
            default:
                return nil
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            let selected = Set(selectedTracks().map(\.id))
            sortRows()
            tableView.reloadData()
            // Keep the same songs selected after re-sorting.
            let rows = IndexSet(order.indices.filter { selected.contains(tracks[order[$0]].id) })
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            if !isUpdating { notifySelection() }
        }

        private func selectedTracks() -> [Track] {
            guard let tableView else { return [] }
            return tableView.selectedRowIndexes.compactMap { order.indices.contains($0) ? tracks[order[$0]] : nil }
        }

        private func notifySelection() { onSelect(selectedTracks()) }

        // MARK: Menus

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let tableView else { return }
            menu.removeAllItems()
            if menu === tableView.headerView?.menu {
                // Show or hide columns (Title always stays).
                for column in tableView.tableColumns where column.identifier.rawValue != "title" {
                    let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = column
                    item.state = column.isHidden ? .off : .on
                    menu.addItem(item)
                }
                return
            }
            // Right-clicking an unselected row acts on that row.
            let clicked = tableView.clickedRow
            if clicked >= 0, !tableView.selectedRowIndexes.contains(clicked) {
                tableView.selectRowIndexes([clicked], byExtendingSelection: false)
            }
            let urls = selectedTracks().compactMap(\.fileURL)
            if onShowInfo != nil {
                let info = NSMenuItem(title: "Show Info", action: #selector(showInfo), keyEquivalent: "")
                info.target = self
                menu.addItem(info)
                menu.addItem(.separator())
            }
            let finder = NSMenuItem(title: "Show in Finder", action: urls.isEmpty ? nil : #selector(showInFinder),
                                    keyEquivalent: "")
            finder.target = self
            menu.addItem(finder)
            let copy = NSMenuItem(title: urls.count > 1 ? "Copy Paths" : "Copy Path",
                                  action: urls.isEmpty ? nil : #selector(copyPaths), keyEquivalent: "")
            copy.target = self
            menu.addItem(copy)
        }

        @objc private func toggleColumn(_ item: NSMenuItem) {
            guard let column = item.representedObject as? NSTableColumn else { return }
            column.isHidden.toggle()
        }

        @objc private func showInfo() { onShowInfo?() }

        @objc private func showInFinder() {
            NSWorkspace.shared.activateFileViewerSelecting(selectedTracks().compactMap(\.fileURL))
        }

        @objc private func copyPaths() {
            let paths = selectedTracks().compactMap(\.fileURL).map(\.path)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        }
    }
}
