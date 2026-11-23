//
//  ChecklistTableView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The Music tab's list of artists, albums, genres or playlists, each with
//  a checkbox (ticked = synced to this Q2), an optional subtitle (an
//  album's artist, a playlist's folder) and a song count.
//
//  HOW IT FITS
//  Used by `DeviceMusicView`. An `NSTableView` with plain reused cells,
//  like the library browser's lists (see `AppKitTableSupport.swift` for
//  why): SwiftUI's `List` hosted a view per row, which made long lists
//  slow to scroll and to switch.
//

import AppKit
import SwiftUI

/// A list of groups with a checkbox each.
struct ChecklistTableView: NSViewRepresentable {

    /// The rows to show (already filtered).
    let rows: [TrackGroup]
    /// The IDs of ticked rows.
    let ticked: Set<String>
    /// Called when a checkbox is clicked: the row's ID and its new state.
    let onToggle: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .none // The checkboxes are the choice.
        tableView.headerView = nil
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.minWidth = 120
        tableView.addTableColumn(name)
        let count = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("count"))
        count.width = 56
        count.minWidth = 40
        count.maxWidth = 80
        tableView.addTableColumn(count)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onToggle = onToggle
        context.coordinator.update(rows: rows, ticked: ticked)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {

        weak var tableView: NSTableView?
        var onToggle: (String, Bool) -> Void = { _, _ in }
        private var rows: [TrackGroup] = []
        private var rowIDs: [String] = []
        private var ticked: Set<String> = []

        /// A different list (another section, or the filter) reloads and
        /// scrolls to the top; changed ticks only redraw the rows in place.
        func update(rows newRows: [TrackGroup], ticked newTicked: Set<String>) {
            guard let tableView else { return }
            let newIDs = newRows.map(\.id)
            if newIDs != rowIDs {
                rows = newRows
                rowIDs = newIDs
                ticked = newTicked
                tableView.reloadData()
                if !rows.isEmpty { tableView.scrollRowToVisible(0) }
            } else if newTicked != ticked || newRows != rows {
                rows = newRows
                ticked = newTicked
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count),
                                     columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            rows.indices.contains(row) && rows[row].subtitle != nil ? 36 : 24
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let id = tableColumn?.identifier.rawValue, rows.indices.contains(row) else { return nil }
            let item = rows[row]
            switch id {
            case "name":
                return checkboxCell(tableView, item: item, row: row)
            case "count":
                return TableCells.text(tableView, id: id, item.trackIDs.count.formatted(), secondary: true,
                                       monospacedDigits: true, alignment: .right)
            default:
                return nil
            }
        }

        /// A checkbox titled with the row's name, and its subtitle below.
        private func checkboxCell(_ tableView: NSTableView, item: TrackGroup, row: Int) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("checkbox")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
                box.lineBreakMode = .byTruncatingTail
                box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                let subtitle = NSTextField(labelWithString: "")
                subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                subtitle.textColor = .secondaryLabelColor
                subtitle.lineBreakMode = .byTruncatingTail
                subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                subtitle.translatesAutoresizingMaskIntoConstraints = false
                // Indented to line up with the checkbox's title.
                let indent = NSView()
                indent.addSubview(subtitle)
                NSLayoutConstraint.activate([
                    subtitle.leadingAnchor.constraint(equalTo: indent.leadingAnchor, constant: 20),
                    subtitle.trailingAnchor.constraint(equalTo: indent.trailingAnchor),
                    subtitle.topAnchor.constraint(equalTo: indent.topAnchor),
                    subtitle.bottomAnchor.constraint(equalTo: indent.bottomAnchor),
                ])
                let stack = NSStackView(views: [box, indent])
                stack.orientation = .vertical
                stack.alignment = .leading
                stack.spacing = 0
                stack.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                    stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            let views = (cell.subviews.first as? NSStackView)?.arrangedSubviews ?? []
            if let box = views.first as? NSButton {
                box.title = item.title
                box.state = ticked.contains(item.id) ? .on : .off
                box.tag = row
                box.target = self
                box.toolTip = item.title
            }
            if views.count > 1, let indent = views.last, let subtitle = indent.subviews.first as? NSTextField {
                subtitle.stringValue = item.subtitle ?? ""
                indent.isHidden = item.subtitle == nil
            }
            return cell
        }

        @objc private func toggled(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag) else { return }
            let id = rows[sender.tag].id
            let isOn = sender.state == .on
            // Keep our copy in step so a redraw before SwiftUI's update
            // doesn't flip the box back.
            if isOn { ticked.insert(id) } else { ticked.remove(id) }
            onToggle(id, isOn)
        }
    }
}
