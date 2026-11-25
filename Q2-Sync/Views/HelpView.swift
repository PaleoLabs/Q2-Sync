//
//  HelpView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The help window (Help › Q2 Sync Help, ⌘?): the user guide's sections in
//  a sidebar and the selected one on the right.
//
//  HOW IT FITS
//  The build copies `docs/USER_GUIDE.md` into the app, so the window works
//  offline and describes the installed version. `UserGuide` (in Core) parses
//  it; this file only draws the result. Links to headings move around the
//  window, and all other links open in the browser.
//

import SwiftUI

/// The help window's content.
struct HelpView: View {

    /// A heading to show: the section holding it, and where to scroll.
    private struct Place: Equatable {
        var section: String
        /// A heading to scroll to, or `nil` for the top.
        var heading: String?
        /// Makes each visit new, so a link followed twice scrolls twice.
        let visit = UUID()
    }

    /// The guide, read once. `nil` if the app has no readable copy.
    private static let guide: UserGuide? = {
        guard let url = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Written into Info.plist by `Scripts/stamp-version.sh`.
        let commit = Bundle.main.infoDictionary?["Q2SyncBuildCommit"] as? String
        return try? UserGuide(markdown: markdown,
                              webAddress: UserGuide.webAddress(commit: commit))
    }()

    @State private var place = Place(section: guide?.sections.first?.id ?? "")

    var body: some View {
        if let guide = Self.guide {
            NavigationSplitView {
                List(guide.sections, selection: selectedSection) { section in
                    Text(section.title)
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
            } detail: {
                if let section = guide.sections.first(where: { $0.id == place.section }) {
                    page(section)
                        // A new section starts a new scroll view, at the top.
                        .id(section.id)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard case .anchor(let name) = UserGuide.destination(of: url) else {
                    return .systemAction
                }
                if let section = guide.section(containing: name) {
                    place = Place(section: section.id, heading: name)
                }
                return .handled
            })
        } else {
            ContentUnavailableView {
                Label("Help Isn't Available", systemImage: "questionmark.circle")
            } description: {
                Text("This copy of Q2 Sync has no user guide.")
            } actions: {
                Link("Read It on GitHub", destination: UserGuide.webAddress(commit: nil))
            }
        }
    }

    /// The sidebar's selection. Choosing a section shows its top.
    private var selectedSection: Binding<String?> {
        Binding {
            place.section
        } set: { id in
            if let id { place = Place(section: id) }
        }
    }

    private func page(_ section: UserGuide.Section) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                GuideBlocks(blocks: section.blocks)
                    .textSelection(.enabled)
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: place) {
                if let heading = place.heading { scroller.scrollTo(heading, anchor: .top) }
            }
        }
    }
}

/// Blocks of the guide, one under another.
private struct GuideBlocks: View {

    let blocks: [UserGuide.Block]
    var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                GuideBlock(block: block)
            }
        }
    }
}

/// One block of the guide.
private struct GuideBlock: View {

    let block: UserGuide.Block

    var body: some View {
        switch block {
        case .heading(let level, let text, let anchor):
            Text(text)
                .font(level == 1 ? .largeTitle : level == 2 ? .title : .title3)
                .bold()
                .padding(.top, level > 2 ? 8 : 0)
                .accessibilityAddTraits(.isHeader)
                .id(anchor)
        case .paragraph(let text):
            wrapping(text)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: ordered ? "\(item.number)." : "•")
                            .monospacedDigit()
                            .frame(minWidth: 18, alignment: .trailing)
                        GuideBlocks(blocks: item.blocks, spacing: 6)
                    }
                }
            }
        case .quote(let blocks):
            GuideBlocks(blocks: blocks)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Capsule().fill(.tertiary).frame(width: 3)
                }
        case .table(let header, let rows):
            // Rows of fixed and flexible columns rather than a `Grid`,
            // which left gaps under some rows or cut wrapped text short.
            VStack(alignment: .leading, spacing: 8) {
                tableRow(header).bold()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    tableRow(row)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        case .code(let code):
            Text(verbatim: code)
                .font(.body.monospaced())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        case .divider:
            Divider()
        }
    }

    /// A table row: a narrow first column, the rest sharing what's left.
    private func tableRow(_ cells: [AttributedString]) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                if column == 0 {
                    wrapping(cell).frame(width: 170, alignment: .leading)
                } else {
                    wrapping(cell).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Text that wraps onto as many lines as it needs.
    private func wrapping(_ text: AttributedString) -> some View {
        Text(text)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
