//
//  UserGuideTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the help window's reading of the user guide, including checks
//  on the real `docs/USER_GUIDE.md`: if it gains something the window can't
//  show, or a link to a heading that isn't there, these fail.
//

import Foundation
import Testing
@testable import Q2SyncCore

/// The plain text of each block, with the tree shown by brackets.
private func outline(_ blocks: [UserGuide.Block]) -> [String] {
    blocks.map { block in
        switch block {
        case .heading(let level, let text, _): "h\(level) \(String(text.characters))"
        case .paragraph(let text): "p \(String(text.characters))"
        case .list(let ordered, let items):
            (ordered ? "ol " : "ul ")
                + items.map { "\($0.number)\(outline($0.blocks))" }.joined(separator: " ")
        case .quote(let blocks): "quote \(outline(blocks))"
        case .table(let header, let rows):
            "table " + ([header] + rows)
                .map { $0.map { String($0.characters) }.joined(separator: "|") }
                .joined(separator: " / ")
        case .code(let code): "code \(code)"
        case .divider: "divider"
        }
    }
}

/// Every link in a section, in order.
private func links(_ blocks: [UserGuide.Block]) -> [URL] {
    blocks.flatMap { block -> [URL] in
        switch block {
        case .heading(_, let text, _), .paragraph(let text): text.runs.compactMap(\.link)
        case .list(_, let items): items.flatMap { links($0.blocks) }
        case .quote(let blocks): links(blocks)
        case .table(let header, let rows):
            ([header] + rows).joined().flatMap { $0.runs.compactMap(\.link) }
        case .code, .divider: []
        }
    }
}

@Suite("User guide parsing")
struct UserGuideParsingTests {

    @Test("Sections come from level-2 headings, without the table of contents")
    func sections() throws {
        let guide = try UserGuide(markdown: """
        # Title

        Opening words.

        ## Contents

        1. [First](#1-first)

        ---

        ## 1. First

        Text.

        ---

        ## What's new?

        More.
        """)
        #expect(guide.sections.map(\.title) == ["Introduction", "1. First", "What's new?"])
        #expect(guide.sections.map(\.id) == ["introduction", "1-first", "whats-new"])
        #expect(outline(guide.sections[1].blocks) == ["h2 1. First", "p Text."])
        #expect(guide.problems.isEmpty)
    }

    @Test("Wrapped lines join into one paragraph")
    func wrapping() throws {
        let guide = try UserGuide(markdown: "## A\n\nOne line\nand the next.")
        #expect(outline(guide.sections[0].blocks) == ["h2 A", "p One line and the next."])
    }

    @Test("Nested lists, quotes and code keep their structure")
    func nesting() throws {
        let guide = try UserGuide(markdown: """
        ## A

        1. One
        2. Two:
           - inner

        > Note
        > - point

        ```
        swift test
        ```
        """)
        #expect(outline(guide.sections[0].blocks) == [
            "h2 A",
            #"ol 1["p One"] 2["p Two:", "ul 1[\"p inner\"]"]"#,
            #"quote ["p Note", "ul 1[\"p point\"]"]"#,
            "code swift test",
        ])
        #expect(guide.problems.isEmpty)
    }

    @Test("Tables keep empty cells in their columns")
    func tables() throws {
        let guide = try UserGuide(markdown: """
        ## A

        | Name | Note |
        | --- | --- |
        | | **bold** |
        | b | |
        """)
        #expect(outline(guide.sections[0].blocks) == ["h2 A", "table Name|Note / |bold / b|"])
    }

    @Test("Links go to a heading, a repository file or the web")
    func linkDestinations() throws {
        let guide = try UserGuide(
            markdown: """
            ## A

            [down](#b-part) [file](../CONTRIBUTING.md) [web](https://example.com/x#y)

            ### B part
            """,
            webAddress: UserGuide.webAddress(commit: "a3026c0")
        )
        #expect(links(guide.sections[0].blocks).map(UserGuide.destination(of:)) == [
            .anchor("b-part"),
            .external(URL(string: "https://github.com/PaleoLabs/Q2-Sync/blob/a3026c0/CONTRIBUTING.md")!),
            .external(URL(string: "https://example.com/x#y")!),
        ])
        #expect(guide.section(containing: "b-part")?.id == "a")
        #expect(guide.problems.isEmpty)
    }

    @Test("Builds without a plain commit hash link to the main branch",
          arguments: [nil, "", "unknown", "a3026c0-dirty"])
    func webAddressFallback(commit: String?) {
        #expect(UserGuide.webAddress(commit: commit).path.contains("/blob/main/"))
    }

    @Test("Repeated headings get numbered anchors, as on GitHub")
    func repeatedHeadings() throws {
        let guide = try UserGuide(markdown: "## Same\n\na\n\n## Same\n\nb")
        #expect(guide.sections.map(\.id) == ["same", "same-1"])
    }

    @Test("A link to a missing heading is reported")
    func brokenLink() throws {
        let guide = try UserGuide(markdown: "## A\n\n[x](#nowhere)")
        #expect(guide.problems == ["Link to a missing heading: #nowhere"])
    }

    @Test("Images and HTML are reported and still show as text",
          arguments: ["![Sync window](sync.png)", "Press <kbd>Sync window</kbd>",
                      "<div>Sync window</div>"])
    func unsupported(markdown: String) throws {
        let guide = try UserGuide(markdown: "## A\n\n\(markdown)")
        #expect(!guide.problems.isEmpty)
        #expect(outline(guide.sections[0].blocks).joined().contains("Sync window"))
    }
}

@Suite("The real user guide")
struct RealUserGuideTests {

    /// The repository folder, found from this file's own path.
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func guide() throws -> UserGuide {
        let url = Self.repository.appending(path: "docs/USER_GUIDE.md")
        return try UserGuide(markdown: String(contentsOf: url, encoding: .utf8))
    }

    @Test("Everything in it can be shown and every section link works")
    func noProblems() throws {
        #expect(try guide().problems == [])
    }

    @Test("It has an introduction and numbered sections")
    func sections() throws {
        let titles = try guide().sections.map(\.title)
        #expect(titles.first == "Introduction")
        #expect(titles.count > 1)
        #expect(!titles.contains("Contents"))
    }

    @Test("Its links to repository files point at files that exist")
    func fileLinks() throws {
        let prefix = "/PaleoLabs/Q2-Sync/blob/main/"
        for url in try guide().sections.flatMap({ links($0.blocks) }) {
            guard url.host() == "github.com", url.path.hasPrefix(prefix) else { continue }
            let file = Self.repository.appending(path: String(url.path.dropFirst(prefix.count)))
            #expect(FileManager.default.fileExists(atPath: file.path), "\(url)")
        }
    }
}
