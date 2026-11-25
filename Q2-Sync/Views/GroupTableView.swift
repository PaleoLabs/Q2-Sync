//
//  GroupTableView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The library browser's list of artists, albums, genres or playlists,
//  with where each stands with the Q2 (lock for songs that can't be
//  copied, then on the Q2 / partly / next sync) and its song count.
//
//  HOW IT FITS
//  The left pane of `LibraryCategoryView`. An `NSTableView` wrapped for
//  SwiftUI, like `TrackTableView` (see `AppKitTableSupport.swift` for
//  why): plain reused cells however long the list is.
//

import AppKit
import SwiftUI

/// One row of the group list: the group plus its marks.
struct GroupRow: Identifiable, Equatable {
    let group: TrackGroup
    let marks: GroupMarks?
    let hasQ2: Bool
    var id: String { group.id }

    /// What the row shows, without comparing every song ID in the group
    /// (a big genre holds thousands). A group's songs only change with a
    /// new library read, which rebuilds the marks too.
    static func == (a: GroupRow, b: GroupRow) -> Bool {
        a.group.id == b.group.id && a.group.title == b.group.title && a.group.subtitle == b.group.subtitle
            && a.group.trackIDs.count == b.group.trackIDs.count && a.marks == b.marks && a.hasQ2 == b.hasQ2
    }
}

/// The list of groups, with single selection.
struct GroupTableView: NSViewRepresentable {

    let rows: [GroupRow]
    /// The first column's title, e.g. "Artist".
    let title: String
    /// The selected group's ID.
    @Binding var selection: String?
    /// A group's song files, for the right-click menu's "Show in Finder".
    var files: (TrackGroup) -> [URL] = { _ in [] }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.title = title
        name.minWidth = 120
        tableView.addTableColumn(name)
        let q2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("q2"))
        q2.title = "On Q2"
        q2.width = 48
        q2.minWidth = 48
        q2.maxWidth = 48
        tableView.addTableColumn(q2)
        let songs = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("songs"))
        songs.title = "Songs"
        songs.width = 48
        songs.minWidth = 40
        songs.maxWidth = 80
        songs.headerCell.alignment = .right
        tableView.addTableColumn(songs)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView
        let rowMenu = NSMenu()
        rowMenu.delegate = context.coordinator
        tableView.menu = rowMenu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $selection
        coordinator.files = files
        coordinator.tableView?.tableColumns.first?.title = title
        coordinator.update(rows: rows, selection: selection)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

        weak var tableView: NSTableView?
        var selection: Binding<String?>
        var files: (TrackGroup) -> [URL] = { _ in [] }
        private var rows: [GroupRow] = []
        private var rowIDs: [String] = []
        /// `true` while applying an update from SwiftUI (see
        /// `TrackTableView.Coordinator.isUpdating`).
        private var isUpdating = false

        init(selection: Binding<String?>) { self.selection = selection }

        func update(rows newRows: [GroupRow], selection selected: String?) {
            guard let tableView else { return }
            isUpdating = true
            defer { isUpdating = false }
            let newIDs = newRows.map(\.id)
            if newIDs != rowIDs {
                rows = newRows
                rowIDs = newIDs
                tableView.reloadData()
            } else if newRows != rows {
                rows = newRows
                // Marks changed: redraw rows in place (keeps the selection).
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count),
                                     columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            }
            // Follow the selection SwiftUI holds (cleared when the
            // category changes, say).
            let wanted = selected.flatMap { rowIDs.firstIndex(of: $0) }
            if tableView.selectedRow != (wanted ?? -1) {
                if let wanted {
                    tableView.selectRowIndexes([wanted], byExtendingSelection: false)
                    tableView.scrollRowToVisible(wanted)
                } else {
                    tableView.deselectAll(nil)
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            rows.indices.contains(row) && rows[row].group.subtitle != nil ? 34 : 22
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let id = tableColumn?.identifier.rawValue, rows.indices.contains(row) else { return nil }
            let item = rows[row]
            switch id {
            case "name":
                return TableCells.twoLine(tableView, title: item.group.title, subtitle: item.group.subtitle)
            case "q2":
                // Two fixed slots: can't-copy lock, then the Q2 state.
                let lock = item.marks.flatMap(TableIcon.groupLock)
                let q2 = item.hasQ2 ? item.marks.flatMap(TableIcon.groupQ2) : nil
                return TableCells.icons(tableView, id: id, [lock, q2])
            case "songs":
                return TableCells.text(tableView, id: id, (item.marks?.total ?? item.group.trackIDs.count).formatted(),
                                       secondary: true, monospacedDigits: true, alignment: .right)
            default:
                return nil
            }
        }

        /// The right-click menu for a row. It acts on that row without
        /// changing the selection.
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let row = tableView?.clickedRow, rows.indices.contains(row) else { return }
            // Dimmed when one Finder window can't show the whole group.
            let items = FinderReveal.items(for: files(rows[row].group))
            let finder = NSMenuItem(title: "Show in Finder", action: items == nil ? nil : #selector(showInFinder(_:)),
                                    keyEquivalent: "")
            finder.target = self
            finder.representedObject = items
            menu.addItem(finder)
        }

        @objc private func showInFinder(_ item: NSMenuItem) {
            guard let urls = item.representedObject as? [URL] else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let tableView else { return }
            let row = tableView.selectedRow
            let id = rows.indices.contains(row) ? rows[row].id : nil
            if selection.wrappedValue != id { selection.wrappedValue = id }
        }
    }
}
