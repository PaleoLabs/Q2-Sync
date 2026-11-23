//
//  AppKitTableSupport.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  Shared pieces for the library browser's two AppKit tables (the group
//  list and the song table): plain text and icon cells, and the icons
//  for where songs and groups stand with the Q2.
//
//  WHY APPKIT
//  SwiftUI's `Table` hosts a SwiftUI view in every cell. Scrolling long
//  lists built thousands of them, and removing them from the window took
//  seconds (each unhooks observers from a shared list), which hung the
//  app. `NSTableView` with plain AppKit cells reuses a screenful of cells
//  however long the list is.
//

import AppKit

/// An icon for a table cell: symbol, colour and tooltip.
struct TableIcon: Equatable {
    let symbol: String
    let color: NSColor
    let help: String

    /// The image, tinted by the image view that shows it.
    var image: NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: help)
    }
}

extension TableIcon {

    private static let asOf = " (from Q2 Sync's record of the card when it was last connected)"

    /// A song's On Q2 icon: on the Q2 (grey check), next sync (blue
    /// arrow), not chosen (none: the cell shows a dash), or can't be
    /// synced (orange, with the reason).
    static func song(_ track: Track, placement: TrackPlacement?) -> TableIcon? {
        if !track.isCopyable {
            return TableIcon(symbol: track.availability.symbolName, color: .systemOrange,
                             help: "Can't be synced: \(track.availability.reportDescription.lowercased()). Select it and open Song Info for more.")
        }
        switch placement {
        case .onQ2:
            return TableIcon(symbol: "checkmark.circle.fill", color: .secondaryLabelColor,
                             help: "On your Q2, as of Q2 Sync's record of the card.")
        case .nextSync:
            return TableIcon(symbol: "arrow.down.circle", color: .systemBlue,
                             help: "Chosen for your Q2 but not copied yet. It goes over at the next sync.")
        case .notChosen, .cantSync, nil:
            return nil
        }
    }

    /// A group's lock: some (outline) or all (filled) songs can't be copied.
    static func groupLock(_ marks: GroupMarks) -> TableIcon? {
        if marks.syncable == 0 {
            return TableIcon(symbol: "lock.fill", color: .systemOrange,
                             help: "None of these songs can be copied. Select it to see why for each song.")
        }
        if marks.syncable < marks.total {
            return TableIcon(symbol: "lock", color: .systemOrange,
                             help: "\(marks.syncable) of \(marks.total) songs can be copied. Select it to see why the others can't.")
        }
        return nil
    }

    /// A group's Q2 state: on the Q2 (check), partly (half circle), coming
    /// at the next sync (blue arrow), or none when not chosen. Quiet on
    /// purpose: the usual case is a grey check.
    static func groupQ2(_ marks: GroupMarks) -> TableIcon? {
        if marks.syncable == 0 && marks.onQ2 == 0 { return nil }
        if marks.onQ2 >= marks.syncable {
            return TableIcon(symbol: "checkmark.circle.fill", color: .secondaryLabelColor,
                             help: "On your Q2" + asOf + ".")
        }
        if marks.onQ2 > 0 {
            let next = marks.nextSync > 0 ? "; \(marks.nextSync) more at the next sync" : ""
            return TableIcon(symbol: "circle.lefthalf.filled", color: .secondaryLabelColor,
                             help: "\(marks.onQ2) of \(marks.syncable) on your Q2\(next)" + asOf + ".")
        }
        if marks.nextSync > 0 {
            return TableIcon(symbol: "arrow.down.circle.fill", color: .systemBlue,
                             help: "\(marks.nextSync) chosen for your Q2 but not copied yet. They go over at the next sync.")
        }
        return nil
    }
}

/// Builds and fills reusable table cells.
enum TableCells {

    /// A one-line text cell, reused by identifier.
    static func text(_ tableView: NSTableView, id: String, _ string: String, secondary: Bool = false,
                     monospacedDigits: Bool = false, alignment: NSTextAlignment = .natural,
                     truncation: NSLineBreakMode = .byTruncatingTail, toolTip: String? = nil) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("text." + id)
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let field = cell.textField!
        field.stringValue = string
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        let size = NSFont.systemFontSize
        field.font = monospacedDigits ? .monospacedDigitSystemFont(ofSize: size, weight: .regular) : .systemFont(ofSize: size)
        field.alignment = alignment
        field.lineBreakMode = truncation
        cell.toolTip = toolTip
        return cell
    }

    /// A two-line cell (title, and a smaller grey subtitle when there is one).
    static func twoLine(_ tableView: NSTableView, title: String, subtitle: String?) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("twoLine")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let titleField = NSTextField(labelWithString: "")
            titleField.lineBreakMode = .byTruncatingTail
            let subtitleField = NSTextField(labelWithString: "")
            subtitleField.lineBreakMode = .byTruncatingTail
            subtitleField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            subtitleField.textColor = .secondaryLabelColor
            for field in [titleField, subtitleField] {
                field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            let stack = NSStackView(views: [titleField, subtitleField])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 1
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(stack)
            cell.textField = titleField
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let fields = (cell.subviews.first as? NSStackView)?.arrangedSubviews.compactMap { $0 as? NSTextField } ?? []
        fields.first?.stringValue = title
        if fields.count > 1 {
            fields[1].stringValue = subtitle ?? ""
            fields[1].isHidden = subtitle == nil
        }
        cell.toolTip = title
        return cell
    }

    /// A cell with up to two icons side by side, each in a fixed 16-point
    /// slot so icons line up down the column. `nil` leaves a slot empty;
    /// `placeholder` shows a grey dash when both are empty.
    static func icons(_ tableView: NSTableView, id: String, _ icons: [TableIcon?], placeholder: Bool = false) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("icons." + id)
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let views: [NSView] = icons.indices.map { _ in
                let view = NSImageView()
                view.symbolConfiguration = .init(pointSize: NSFont.systemFontSize, weight: .regular)
                view.translatesAutoresizingMaskIntoConstraints = false
                view.widthAnchor.constraint(equalToConstant: 16).isActive = true
                return view
            }
            let dash = NSTextField(labelWithString: "—")
            dash.textColor = .tertiaryLabelColor
            let stack = NSStackView(views: views + [dash])
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let stack = cell.subviews.first as? NSStackView
        let imageViews = stack?.arrangedSubviews.compactMap { $0 as? NSImageView } ?? []
        var tips: [String] = []
        for (view, icon) in zip(imageViews, icons) {
            view.image = icon?.image
            view.contentTintColor = icon?.color
            view.toolTip = icon?.help
            if let help = icon?.help { tips.append(help) }
        }
        let showDash = placeholder && icons.allSatisfy { $0 == nil }
        stack?.arrangedSubviews.last?.isHidden = !showDash
        imageViews.forEach { $0.isHidden = showDash }
        cell.toolTip = tips.isEmpty ? (showDash ? "Not chosen for your Q2. Choose it on the Q2's Music tab." : nil) : tips.joined(separator: "\n")
        return cell
    }
}
