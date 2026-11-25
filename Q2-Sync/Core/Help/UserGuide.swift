//
//  UserGuide.swift
//  Q2-Sync › Core › Help
//
//  PURPOSE
//  Turns the user guide's Markdown (`docs/USER_GUIDE.md`) into sections and
//  blocks the help window can draw, and works out where each link goes.
//
//  HOW IT FITS
//  `HelpView` loads the copy of the guide bundled with the app and draws
//  these blocks. Everything here is plain data, so it can be unit tested,
//  including against the real guide.
//
//  HOW PARSING WORKS
//  Foundation does the Markdown parsing. It returns one long
//  `AttributedString` in which every run of text says which blocks it sits
//  in (`presentationIntent`), for example "paragraph, inside list item 2,
//  inside an ordered list". We group neighbouring runs by those blocks to
//  rebuild the tree.
//
//  NOTHING IS HARD-CODED
//  Sections come from the `##` headings and link targets from the heading
//  text, so editing the guide needs no code change. Anything the window
//  can't draw (images, HTML) is shown as plain text and listed in
//  `problems`, which a test requires to be empty for the real guide.
//

import Foundation

/// The user guide, ready to display.
struct UserGuide: Sendable {

    /// One piece of a page.
    enum Block: Sendable {
        /// A heading. `anchor` is the name links use to reach it.
        case heading(level: Int, text: AttributedString, anchor: String)
        case paragraph(AttributedString)
        case list(ordered: Bool, items: [ListItem])
        case quote([Block])
        /// A table. Every row has as many cells as `header`.
        case table(header: [AttributedString], rows: [[AttributedString]])
        case code(String)
        case divider
    }

    /// One bullet or numbered entry, which may hold further blocks.
    struct ListItem: Sendable {
        /// The number shown in an ordered list.
        let number: Int
        var blocks: [Block]
    }

    /// One page of the guide: a `##` heading and everything under it.
    struct Section: Sendable, Identifiable {
        /// The heading's anchor (or "introduction" for the opening text).
        let id: String
        /// The title shown in the sidebar.
        let title: String
        let blocks: [Block]
    }

    /// Where a link in the guide leads.
    enum Destination: Equatable, Sendable {
        /// A heading in this guide.
        case anchor(String)
        /// Anything else: opened in the browser or by macOS.
        case external(URL)
    }

    /// The opening text (if any), then one section per `##` heading.
    let sections: [Section]

    /// What the window can't show properly: links to headings that don't
    /// exist, and unsupported content. Empty for a healthy guide.
    let problems: [String]

    /// The scheme marking links that stay inside the help window.
    static let anchorScheme = "q2sync-guide"

    /// The heading of the guide's own table of contents, which the sidebar
    /// replaces.
    private static let contentsTitle = "Contents"

    /// The section that contains the heading named `anchor`.
    func section(containing anchor: String) -> Section? {
        sections.first { section in
            section.id == anchor || section.blocks.contains { block in
                if case .heading(_, _, let name) = block { return name == anchor }
                return false
            }
        }
    }

    /// Reads back a link from the parsed text.
    static func destination(of url: URL) -> Destination {
        guard url.scheme == anchorScheme else { return .external(url) }
        let name = String(url.absoluteString.dropFirst(anchorScheme.count + 1))
        return .anchor(name.removingPercentEncoding ?? name)
    }

    /// The web address of the guide at `commit`, used to resolve its links
    /// to other files in the repository.
    ///
    /// - Parameter commit: The commit the app was built from. Anything that
    ///   isn't a plain commit hash (an unknown or "-dirty" build) uses the
    ///   `main` branch instead.
    static func webAddress(commit: String?) -> URL {
        let isHash = commit.map { !$0.isEmpty && $0.allSatisfy(\.isHexDigit) } ?? false
        let ref = isHash ? commit! : "main"
        return URL(string: "https://github.com/PaleoLabs/Q2-Sync/blob/\(ref)/docs/USER_GUIDE.md")!
    }

    /// The name GitHub gives a heading, so `[text](#name)` links work both
    /// there and here: lower case, punctuation removed, spaces as hyphens.
    static func anchor(for heading: String) -> String {
        String(heading.lowercased().compactMap { character -> Character? in
            if character == " " { return "-" }
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return nil
        })
    }

    /// Parses the guide.
    ///
    /// - Parameters:
    ///   - markdown: The guide's text.
    ///   - webAddress: Where the guide lives on the web; links to other
    ///     files are resolved against it.
    /// - Throws: If Foundation can't parse the text at all.
    init(markdown: String, webAddress: URL = UserGuide.webAddress(commit: nil)) throws {
        let text = try AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        )
        var builder = Builder(webAddress: webAddress)
        let runs = text.runs.map { run in
            Builder.Run(
                // Foundation lists the innermost block first.
                path: (run.presentationIntent?.components ?? []).reversed(),
                text: builder.inline(AttributedString(text[run.range]))
            )
        }
        let blocks = builder.blocks(from: runs[...], depth: 0)
        sections = Self.split(blocks)

        let anchors = Set(sections.flatMap { section in
            [section.id] + section.blocks.compactMap { block in
                if case .heading(_, _, let name) = block { return name }
                return nil
            }
        })
        let broken = builder.linkedAnchors
            .filter { !anchors.contains($0) }
            .map { "Link to a missing heading: #\($0)" }
        problems = builder.problems + broken
    }

    /// Splits the page at each `##` heading, dropping the table of contents
    /// and the divider lines between sections.
    private static func split(_ blocks: [Block]) -> [Section] {
        var sections: [Section] = []
        var id = "introduction"
        var title = "Introduction"
        var current: [Block] = []

        func finish() {
            while case .divider = current.last { current.removeLast() }
            if !current.isEmpty && title != contentsTitle {
                sections.append(Section(id: id, title: title, blocks: current))
            }
            current = []
        }

        for block in blocks {
            if case .heading(2, let text, let anchor) = block {
                finish()
                id = anchor
                title = String(text.characters)
            }
            current.append(block)
        }
        finish()
        return sections
    }
}

/// Rebuilds the block tree from Foundation's flat list of text runs,
/// collecting anchors, links and problems on the way.
private struct Builder {

    /// A stretch of text and the blocks it sits in, outermost first.
    struct Run {
        let path: [PresentationIntent.IntentType]
        let text: AttributedString
    }

    let webAddress: URL
    var problems: [String] = []
    /// Every in-guide link, checked once all headings are known.
    var linkedAnchors: [String] = []
    /// How often each anchor has appeared: GitHub numbers repeats.
    private var anchorUses: [String: Int] = [:]

    init(webAddress: URL) {
        self.webAddress = webAddress
    }

    /// Prepares one run's text: rewrites its link and notes content that
    /// can't be drawn.
    mutating func inline(_ run: AttributedString) -> AttributedString {
        var run = run
        if let link = run.link {
            if link.scheme != nil {
                // Already a complete address.
            } else if link.relativeString.hasPrefix("#") {
                let name = String(link.relativeString.dropFirst())
                let decoded = name.removingPercentEncoding ?? name
                linkedAnchors.append(decoded)
                run.link = URL(string: "\(UserGuide.anchorScheme):\(name)")
            } else {
                run.link = URL(string: link.relativeString, relativeTo: webAddress)?.absoluteURL
            }
        }
        if let image = run.imageURL {
            problems.append("Image: \(image.relativeString)")
            run.imageURL = nil
        }
        if let intent = run.inlinePresentationIntent,
           intent.contains(.inlineHTML) || intent.contains(.blockHTML) {
            problems.append("HTML: \(String(run.characters))")
            // Show the source rather than letting it disappear.
            run.inlinePresentationIntent = .code
        }
        return run
    }

    /// The blocks formed by `runs`, looking `depth` levels into each path.
    mutating func blocks(from runs: ArraySlice<Run>, depth: Int) -> [UserGuide.Block] {
        groups(of: runs, depth: depth).flatMap { component, runs -> [UserGuide.Block] in
            guard let component else {
                // Text outside any block (block HTML, for instance).
                return [.paragraph(joined(runs))]
            }
            switch component.kind {
            case .paragraph:
                return [.paragraph(joined(runs))]
            case .header(let level):
                let text = joined(runs)
                return [.heading(level: level, text: text,
                                 anchor: uniqueAnchor(String(text.characters)))]
            case .orderedList:
                return [.list(ordered: true, items: items(from: runs, depth: depth + 1))]
            case .unorderedList:
                return [.list(ordered: false, items: items(from: runs, depth: depth + 1))]
            case .blockQuote:
                return [.quote(blocks(from: runs, depth: depth + 1))]
            case .table(let columns):
                return [table(from: runs, columns: columns.count, depth: depth + 1)]
            case .codeBlock:
                var code = String(joined(runs).characters)
                if code.hasSuffix("\n") { code.removeLast() }
                return [.code(code)]
            case .thematicBreak:
                return [.divider]
            default:
                problems.append("Unsupported block: \(component.kind)")
                return [.paragraph(joined(runs))]
            }
        }
    }

    private mutating func items(from runs: ArraySlice<Run>, depth: Int) -> [UserGuide.ListItem] {
        groups(of: runs, depth: depth).map { component, runs in
            var number = 1
            if case .listItem(let ordinal) = component?.kind { number = ordinal }
            return UserGuide.ListItem(number: number, blocks: blocks(from: runs, depth: depth + 1))
        }
    }

    /// Builds a table. Foundation reports no text for an empty cell, so
    /// cells are placed by column number.
    private func table(from runs: ArraySlice<Run>, columns: Int, depth: Int) -> UserGuide.Block {
        let empty = Array(repeating: AttributedString(), count: columns)
        var header = empty
        var rows: [[AttributedString]] = []
        for (row, runs) in groups(of: runs, depth: depth) {
            var cells = empty
            for (cell, runs) in groups(of: runs, depth: depth + 1) {
                if case .tableCell(let column) = cell?.kind, cells.indices.contains(column) {
                    cells[column] = joined(runs)
                }
            }
            if case .tableHeaderRow = row?.kind {
                header = cells
            } else {
                rows.append(cells)
            }
        }
        return .table(header: header, rows: rows)
    }

    /// Splits `runs` into neighbouring groups that share the same block at
    /// `depth`.
    private func groups(of runs: ArraySlice<Run>, depth: Int)
        -> [(PresentationIntent.IntentType?, ArraySlice<Run>)] {
        func component(_ run: Run) -> PresentationIntent.IntentType? {
            run.path.indices.contains(depth) ? run.path[depth] : nil
        }
        var result: [(PresentationIntent.IntentType?, ArraySlice<Run>)] = []
        var start = runs.startIndex
        while start < runs.endIndex {
            let first = component(runs[start])
            var end = start + 1
            while end < runs.endIndex, component(runs[end])?.identity == first?.identity {
                end += 1
            }
            result.append((first, runs[start..<end]))
            start = end
        }
        return result
    }

    private func joined(_ runs: ArraySlice<Run>) -> AttributedString {
        var text = runs.reduce(into: AttributedString()) { $0 += $1.text }
        text.presentationIntent = nil
        return text
    }

    private mutating func uniqueAnchor(_ heading: String) -> String {
        let name = UserGuide.anchor(for: heading)
        let uses = anchorUses[name, default: 0]
        anchorUses[name] = uses + 1
        return uses == 0 ? name : "\(name)-\(uses)"
    }
}
