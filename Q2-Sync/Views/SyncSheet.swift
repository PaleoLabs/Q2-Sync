//
//  SyncSheet.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The sheet that walks through a sync: "Preparing…", then the preview of
//  what will change (with removal choices and safety warnings), then
//  progress with Cancel, then the result with the "update the library on
//  your Q2" reminder.
//
//  HOW IT FITS
//  Presented by `RootView` whenever `SyncCoordinator.phase` isn't idle.
//  Each phase has its own small view below.
//

import AppKit
import SwiftUI

/// Switches between the sync phases.
struct SyncSheet: View {

    let sync: SyncCoordinator
    let devices: DeviceMonitor

    var body: some View {
        Group {
            switch sync.phase {
            case .idle:
                EmptyView()
            case .planning(let message):
                VStack(spacing: 14) {
                    ProgressView()
                    Text(message)
                    Button("Cancel") { sync.close() }
                }
                .padding(32)
                .frame(width: 360)
            case .preview:
                if let preview = sync.preview {
                    SyncPreviewView(preview: preview, sync: sync, devices: devices)
                }
            case .running:
                SyncProgressView(sync: sync)
            case .finished:
                if let report = sync.report {
                    SyncResultView(report: report, profile: sync.preview?.profile ?? .q2Pod,
                                   sync: sync, devices: devices)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 14) {
                    Label("Sync Stopped", systemImage: "xmark.octagon.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.red)
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("OK") { sync.close() }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .frame(width: 440)
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Preview

/// Shows what a sync would do and lets the user apply it.
struct SyncPreviewView: View {

    let preview: SyncPreview
    let sync: SyncCoordinator
    let devices: DeviceMonitor

    /// Shows the "remove more than 20%?" confirmation.
    @State private var confirmingLargeRemoval = false

    /// Shows the "permanently delete card-only files?" confirmation.
    @State private var confirmingDeletes = false

    /// Filters every list in the preview (title, artist, album or path).
    @State private var searchText = ""

    /// Sections the user opened or closed, by section ID. Sections the user
    /// hasn't touched use `defaultExpanded(_:count:)`.
    @State private var expansion: [String: Bool] = [:]

    /// Counts and lists, closed by default; remembered between syncs.
    @AppStorage("syncPreviewShowsDetails") private var showsDetails = false

    /// Card-only albums the user opened, by `CardOnlyAlbum.id`.
    @State private var expandedAlbums: Set<String> = []

    /// Sections with more items than this start collapsed, so a first sync
    /// of thousands of songs doesn't bury the sections that need attention.
    private static let collapseThreshold = 200

    private var plan: SyncPlan { preview.plan }
    private var assessment: SafetyAssessment { preview.assessment(for: sync.options) }

    /// Removal percentage for the user's current choices.
    private var removalPercent: Int {
        Int((plan.removalFraction(cardOnlyActions: sync.options.cardOnlyActions,
                                  includeRemovals: sync.options.applyRemovals) * 100).rounded())
    }

    /// Card-only files set to "Delete from Card".
    private var cardOnlyDeleteCount: Int {
        plan.cardOnly.filter { sync.options.cardOnlyActions[$0.path] == .delete }.count
    }

    /// `true` if the user chose any action other than Leave for card-only files.
    private var hasCardOnlyWork: Bool {
        plan.cardOnly.contains { (sync.options.cardOnlyActions[$0.path] ?? .leave) != .leave }
    }

    /// Nothing to copy, rename, remove or decide.
    private var isUpToDate: Bool { plan.isEmpty && !hasCardOnlyWork }

    /// Up to date with no lists worth showing (nothing skipped, nothing
    /// only on the card), so the list area shows a centred message.
    private var hasNothingToList: Bool { plan.isEmpty && plan.cardOnly.isEmpty && plan.skipped.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)
            if showsDetails {
                Divider()
                counts
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                if !hasNothingToList {
                    Divider()
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Divider()
                    details
                }
            }
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 660, height: showsDetails && !hasNothingToList ? 680 : nil)
        .confirmationDialog("Permanently delete \(cardOnlyDeleteCount) files from the card?",
                            isPresented: $confirmingDeletes) {
            Button("Delete \(cardOnlyDeleteCount) Files and Sync", role: .destructive) {
                continueApplying(deletesConfirmed: true)
            }
        } message: {
            Text("These files aren't in your Mac library selection and can't be recovered after deleting. Choose “Move to Mac” instead to keep a copy in Downloads › Q2 Recovered.")
        }
        .confirmationDialog(largeRemovalTitle, isPresented: $confirmingLargeRemoval) {
            Button("Remove and Sync", role: .destructive) {
                sync.options.largeRemovalConfirmed = true
                sync.apply(devices: devices)
            }
        } message: {
            Text("This is more than you usually change. Check the list above. You can turn off removing songs and sync just the additions instead.")
        }
    }

    private var largeRemovalTitle: String {
        "Remove \(removalPercent)% of the songs on “\(preview.deviceName)”?"
    }

    /// Runs the confirmations in order (deletes, then large removals),
    /// then applies.
    private func continueApplying(deletesConfirmed: Bool = false) {
        if cardOnlyDeleteCount > 0 && !deletesConfirmed {
            confirmingDeletes = true
        } else if assessment.needsLargeRemovalConfirmation && !sync.options.largeRemovalConfirmed {
            confirmingLargeRemoval = true
        } else {
            sync.apply(devices: devices)
        }
    }

    // MARK: Header

    /// Title, one plain summary, anything that needs a choice, and the
    /// Details disclosure. Everything else is under Details.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isUpToDate ? "Already Up to Date" : "Ready to Sync")
                .font(.title2.bold())

            Text(summaryText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if preview.isFirstSync && !isUpToDate {
                Label("This is your first sync with this card. Nothing has changed yet.",
                      systemImage: "eye")
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(assessment.blockers, id: \.self) { blocker in
                Label(blocker, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            decisions

            Button {
                withAnimation(.snappy) { showsDetails.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(showsDetails ? 90 : 0))
                    Text("Details")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(showsDetails ? "Hide the counts and lists" : "Show every change, song by song")
        }
    }

    /// e.g. "This sync will update 3 playlists. Everything else is already
    /// on the card. About 158.38 GB will be free on the card."
    private var summaryText: String {
        var text = plan.summary(applyRemovals: sync.options.applyRemovals)
        if !isUpToDate {
            text += " About \(max(0, assessment.projectedFreeBytes).formatted(ByteCountFormatStyle(style: .file))) will be free on the card."
        }
        return text
    }

    /// Card-only groups that have files, in their usual order.
    private var cardOnlyGroups: [CardOnlyGroup] {
        CardOnlyGroup.allCases.filter { group in plan.cardOnly.contains { CardOnlyGroup($0) == group } }
    }

    /// A box for what needs a choice: songs you no longer sync, and music
    /// only on the card (one pop-up per group). Shown only when there's
    /// something to decide.
    @ViewBuilder
    private var decisions: some View {
        if !plan.removals.isEmpty || !cardOnlyGroups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !plan.removals.isEmpty {
                    HStack {
                        Image(systemName: "minus.circle").foregroundStyle(.red)
                        Text("\(plan.removals.count.formatted()) songs you no longer sync are still on the card.")
                        Spacer()
                        Toggle("Remove Them", isOn: Binding(get: { sync.options.applyRemovals },
                                                            set: { sync.options.applyRemovals = $0 }))
                            .toggleStyle(.checkbox)
                    }
                    if assessment.needsLargeRemovalConfirmation {
                        Label("That's \(removalPercent)% of the songs on this card. You'll be asked to confirm.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(cardOnlyGroups) { group in
                    HStack {
                        Image(systemName: "sdcard").foregroundStyle(.teal)
                        Text(group.summary(count: plan.cardOnly.filter { CardOnlyGroup($0) == group }.count))
                        Spacer()
                        cardOnlyGroupPicker(group)
                    }
                }
                Text("Nothing on the card changes unless you choose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// The counts, in one box per topic (Songs, Not Copied, Playlists,
    /// Album Covers), each a short list with the numbers lined up on the
    /// right. Boxes sit side by side; with all four, two by two.
    private var counts: some View {
        let playlists = plan.playlistPlan
        let showsPlaylists = !playlists.writes.isEmpty || !playlists.removals.isEmpty || !playlists.leavingImport.isEmpty
        let showsCovers = !plan.coverWrites.isEmpty || !plan.coverRemovals.isEmpty
        let songs = countBox("Songs") {
            countLine("Add", addCount, "plus.circle.fill", .green)
            countLine("Update", plan.copies.count - addCount, "arrow.triangle.2.circlepath", .blue)
            countLine("Rename", plan.moves.count, "pencil.circle.fill", .purple)
            countLine("Remove", sync.options.applyRemovals ? plan.removals.count : 0, "minus.circle.fill", .red)
        }
        let notCopied = countBox("Not Copied") {
            countLine("Already on card", plan.unchangedCount + plan.adoptions.count, "checkmark.circle.fill", .secondary)
            countLine("On card only", plan.cardOnly.count, "sdcard", .teal)
            countLine("Can't sync", plan.skipped.count, "exclamationmark.circle.fill", .orange)
        }
        let playlistBox = countBox("Playlists") {
            countLine("Playlists", playlists.writes.count, "music.note.list", .pink)
            countLine("Remove playlists", playlists.removals.count, "minus.circle", .red)
            countLine("Already imported", playlists.leavingImport.count, "tray.and.arrow.up", .secondary)
        }
        let coverBox = countBox("Album Covers") {
            countLine("Album covers", plan.coverWrites.count, "photo", .indigo)
            countLine("Remove covers", plan.coverRemovals.count, "minus.circle", .red)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Group {
                if showsPlaylists && showsCovers {
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow { songs; notCopied }
                        GridRow { playlistBox; coverBox }
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        songs
                        notCopied
                        if showsPlaylists { playlistBox }
                        if showsCovers { coverBox }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(spaceSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// One topic's counts in a light rounded box, its name on top.
    private func countBox<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// One count: icon, name, and the number on the right. Zero counts
    /// stay (so "Remove 0" still reassures) but are greyed out.
    private func countLine(_ title: String, _ count: Int, _ symbol: String, _ color: Color) -> some View {
        let dimmed = count == 0
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
                .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            Spacer(minLength: 8)
            Text(count.formatted())
                .monospacedDigit()
                .fontWeight(dimmed ? .regular : .semibold)
                .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        }
    }

    /// e.g. "Copies 1.2 GB · 230.4 GB free afterwards".
    private var spaceSummary: String {
        let style = ByteCountFormatStyle(style: .file)
        let copy = plan.bytesToCopy == 0 ? "Nothing to copy" : "Copies \(Int64(plan.bytesToCopy).formatted(style))"
        let free = max(0, assessment.projectedFreeBytes).formatted(style)
        return "\(copy) · about \(free) free on the card afterwards"
    }

    // MARK: Details

    private var addCount: Int { plan.copies.lazy.filter { $0.kind == .add }.count }

    /// A search box above the list.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by song, artist, album or path", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
            }
        }
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedSearch.isEmpty }

    /// `true` when the filter is empty or any field contains it.
    private func matches(_ fields: String?...) -> Bool {
        let query = trimmedSearch
        guard !query.isEmpty else { return true }
        return fields.contains { $0?.localizedStandardContains(query) == true }
    }

    private func matches(_ track: Track, _ path: String) -> Bool {
        matches(track.title, track.artist, track.albumArtist, track.album, path)
    }

    /// The plan's lists, narrowed by the filter.
    private struct FilteredLists {
        var removals: [RemoveOperation]
        var cardOnly: [CardOnlyItem]
        var playlistWrites: [PlannedPlaylist]
        var playlistRemovals: [PlaylistRemoval]
        var skipped: [Track]
        var adds: [CopyOperation]
        var updates: [CopyOperation]
        var moves: [MoveOperation]
        var adoptions: [AdoptOperation]
        var covers: [CoverWrite]
        var coverRemovals: [CardPath]

        var isEmpty: Bool {
            removals.isEmpty && cardOnly.isEmpty && playlistWrites.isEmpty && playlistRemovals.isEmpty
                && skipped.isEmpty && adds.isEmpty && updates.isEmpty && moves.isEmpty && adoptions.isEmpty
                && covers.isEmpty && coverRemovals.isEmpty
        }
    }

    private func filteredLists() -> FilteredLists {
        let playlists = plan.playlistPlan
        return FilteredLists(
            removals: plan.removals.filter { matches($0.entry.title, $0.entry.artist, $0.entry.album, $0.entry.path) },
            cardOnly: plan.cardOnly.filter { matches($0.title, $0.artist, $0.album, $0.path) },
            playlistWrites: playlists.writes.filter { matches($0.playlist.name, $0.nameOnDevice, $0.path) },
            playlistRemovals: playlists.removals.filter { matches($0.path) },
            skipped: plan.skipped.filter { matches($0, "") },
            adds: plan.copies.filter { $0.kind == .add && matches($0.track, $0.destination) },
            updates: plan.copies.filter { $0.kind == .update && matches($0.track, $0.destination) },
            moves: plan.moves.filter { matches($0.track, $0.from) || matches($0.to) },
            adoptions: plan.adoptions.filter { matches($0.track, $0.path) },
            covers: plan.coverWrites.filter { matches($0.albumName, $0.path) },
            coverRemovals: plan.coverRemovals.filter { matches($0) })
    }

    /// Every planned change, grouped, in a scrollable list. Sections that
    /// need a choice come first, then the rest in the order of the counts
    /// (songs, not copied, playlists, covers). Long lists start collapsed.
    private var details: some View {
        let lists = filteredLists()
        return List {
            // Sections that need a choice first, then the order of the counts.
            removalSection(lists.removals)
            cardOnlySection(lists.cardOnly)
            collapsibleSection("add", "Add", lists.adds) { copy in
                row(copy.track.title, detail: copy.destination, symbol: "plus.circle", color: .green)
            }
            collapsibleSection("update", "Update", lists.updates) { copy in
                row(copy.track.title, detail: "\(copy.destination) — \(copy.reason ?? "")",
                    symbol: "arrow.triangle.2.circlepath", color: .blue)
            }
            collapsibleSection("rename", "Rename", lists.moves) { move in
                row(move.track.title, detail: "\(move.from) → \(move.to)", symbol: "pencil.circle", color: .purple)
            }
            collapsibleSection("skipped", "Can't Sync", lists.skipped, alwaysOpen: true) { track in
                row("\(track.displayArtist) — \(track.title)", detail: track.availability.reportDescription,
                    symbol: track.availability.symbolName, color: .orange)
            }
            collapsibleSection("adopt", "Already on Card — Newly Recorded", lists.adoptions,
                               footer: "The card already had these songs; Q2 Sync now keeps track of them. Nothing is copied."
                                   + (plan.unchangedCount > 0 ? " The other \(plan.unchangedCount.formatted()) were recorded before." : "")) { adoption in
                row(adoption.track.title, detail: adoption.path, symbol: "checkmark.circle", color: .secondary)
            }
            playlistSection(writes: lists.playlistWrites, removals: lists.playlistRemovals)
            collapsibleSection("covers", "Album Covers", lists.covers, footer: "From Apple Music's artwork.") { cover in
                row(cover.albumName, detail: cover.path, symbol: "photo", color: .indigo)
            }
            collapsibleSection("coverRemovals", "Remove Covers", lists.coverRemovals.map(CoverRemovalRow.init),
                               footer: "Album covers are turned off in Settings.") { removal in
                row((removal.path as NSString).deletingLastPathComponent, detail: removal.path,
                    symbol: "minus.circle", color: .red)
            }
            if isSearching && lists.isEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
            }
        }
        .listStyle(.inset)
    }

    /// Removal switches (always shown) and the songs to remove.
    @ViewBuilder
    private func removalSection(_ removals: [RemoveOperation]) -> some View {
        if !plan.removals.isEmpty {
            let expanded = isExpanded("remove", count: plan.removals.count)
            Section {
                Toggle("Remove the \(plan.removals.count.formatted()) songs you no longer sync",
                       isOn: Binding(get: { sync.options.applyRemovals },
                                     set: { sync.options.applyRemovals = $0 }))
                if assessment.needsLargeRemovalConfirmation {
                    Label("That's \(removalPercent)% of the songs on this card. You'll be asked to confirm.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                collapsibleRows(removals, expanded: expanded) { removal in
                    row(removal.entry.title, detail: removal.entry.path, symbol: "minus.circle", color: .red)
                }
                note("Removals are off unless you turn them on. Removed songs are deleted from the card; they're still in your library, so tick them again to put them back. Songs not put there by Q2 Sync are never removed here.")
            } header: {
                sectionHeader("Remove", shown: removals.count, total: plan.removals.count, expanded: expanded)
            }
        }
    }

    /// Music on the card that isn't in the Mac selection, in three groups
    /// (on card only, not put there by Q2 Sync, already in
    /// your library). Each group has one choice; only "Choose Individually"
    /// shows a pop-up on each album and song.
    @ViewBuilder
    private func cardOnlySection(_ items: [CardOnlyItem]) -> some View {
        if !plan.cardOnly.isEmpty {
            let expanded = isExpanded("cardOnly", count: plan.cardOnly.count, alwaysOpen: true)
            Section {
                if expanded.wrappedValue {
                    Text(cardOnlyTally)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(CardOnlyGroup.allCases) { group in
                        let all = plan.cardOnly.filter { CardOnlyGroup($0) == group }
                        let shown = items.filter { CardOnlyGroup($0) == group }
                        if !all.isEmpty {
                            cardOnlyGroup(group, all: all, shown: shown)
                        }
                    }
                    note("Music on the card that isn't part of what you sync. Nothing here changes unless you choose. “Move to Mac” puts the song in Downloads › Q2 Recovered for you to add to Music yourself (it never touches your Music library), then deletes it from the card once the copy is checked.")
                } else {
                    collapsibleRows(items, expanded: expanded) { _ in EmptyView() }
                }
            } header: {
                sectionHeader("On Card Only", shown: items.count, total: plan.cardOnly.count, expanded: expanded)
            }
        }
    }

    /// e.g. "64 leave · 8 copy to Mac · 0 to card trash · 3 delete".
    private var cardOnlyTally: AttributedString {
        let actions = sync.options.cardOnlyActions
        func count(_ action: CardOnlyAction) -> Int {
            action == .leave ? plan.cardOnly.count - actions.count : actions.values.filter { $0 == action }.count
        }
        var text = AttributedString("\(count(.leave).formatted()) leave · \(count(.moveToMac).formatted()) move to Mac · ")
        var deletes = AttributedString("\(count(.delete).formatted()) delete")
        if count(.delete) > 0 { deletes.foregroundColor = .red }
        text.append(deletes)
        return text
    }

    /// One group: its title (left out when it's the only group, as the
    /// section says it already), a line about it, then its albums. Its
    /// choice is in the box at the top.
    @ViewBuilder
    private func cardOnlyGroup(_ group: CardOnlyGroup, all: [CardOnlyItem], shown: [CardOnlyItem]) -> some View {
        let individually = sync.options.cardOnlyChoices.choice(for: group) == .individually
        let single = cardOnlyGroups.count == 1
        let expanded = single ? .constant(true)
            : isExpanded("cardOnly.\(group.rawValue)", count: all.count, alwaysOpen: true)
        if !single {
            Button {
                withAnimation(.snappy) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    Text(isSearching ? "\(group.title) (\(shown.count.formatted()) of \(all.count.formatted()))"
                                     : "\(group.title) (\(all.count.formatted()))")
                        .bold()
                    Spacer()
                    Text(groupChoiceTitle(group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSearching)
        }
        if expanded.wrappedValue {
            Text(group.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(CardOnlyAlbum.group(shown)) { album in
                cardOnlyAlbum(album, group: group, individually: individually)
            }
        }
    }

    /// e.g. "Leave All on Card" or "Choose Individually".
    private func groupChoiceTitle(_ group: CardOnlyGroup) -> String {
        switch sync.options.cardOnlyChoices.choice(for: group) {
        case .all(let action): return action.allTitle
        case .individually: return "Choose Individually"
        }
    }

    /// A group's one choice. "Choose Individually" opens Details, where
    /// each album and song gets its own pop-up.
    private func cardOnlyGroupPicker(_ group: CardOnlyGroup) -> some View {
        let choice = sync.options.cardOnlyChoices.choice(for: group)
        return Picker(group.title, selection: Binding(
            get: { choice },
            set: { newChoice in
                var choices = sync.options.cardOnlyChoices
                choices.setChoice(newChoice, for: group, items: plan.cardOnly)
                sync.options.setCardOnlyChoices(choices, items: plan.cardOnly)
                if newChoice == .individually { withAnimation(.snappy) { showsDetails = true } }
            })) {
            ForEach(group.actions) { Text($0.allTitle).tag(CardOnlyChoices.GroupChoice.all($0)) }
            Divider()
            Text("Choose Individually").tag(CardOnlyChoices.GroupChoice.individually)
        }
        .labelsHidden()
        .fixedSize()
    }

    /// An album row (or a song row, for a lone song). Its songs show when
    /// it's opened, or while filtering.
    @ViewBuilder
    private func cardOnlyAlbum(_ album: CardOnlyAlbum, group: CardOnlyGroup, individually: Bool) -> some View {
        if album.items.count == 1, let item = album.items.first {
            cardOnlySong(item, title: item.displayName, group: group, individually: individually, indent: 16)
        } else {
            let open = isSearching || expandedAlbums.contains(album.id)
            HStack {
                Button {
                    withAnimation(.snappy) {
                        if expandedAlbums.contains(album.id) { expandedAlbums.remove(album.id) }
                        else { expandedAlbums.insert(album.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text("\(album.displayName) · \(album.items.count.formatted()) songs")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(individually ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help((album.items[0].path as NSString).deletingLastPathComponent)
                Spacer()
                sizeText(album.size)
                if individually { albumPicker(album, group: group) }
            }
            .padding(.leading, 16)
            if open {
                ForEach(album.items) { item in
                    cardOnlySong(item, title: album.artist == nil ? item.displayName : (item.title ?? item.displayName),
                                 group: group, individually: individually, indent: 40)
                }
            }
        }
    }

    /// One song: title and size, plus its own pop-up when choosing
    /// individually. The path is in the tooltip and the right-click menu.
    private func cardOnlySong(_ item: CardOnlyItem, title: String, group: CardOnlyGroup,
                              individually: Bool, indent: CGFloat) -> some View {
        HStack {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(individually ? .primary : .secondary)
            Spacer()
            sizeText(UInt64(item.size))
            if individually {
                Picker("Action", selection: Binding(
                    get: { sync.options.cardOnlyChoices.action(for: item) },
                    set: { action in
                        var choices = sync.options.cardOnlyChoices
                        choices.perFile[item.path] = action
                        sync.options.setCardOnlyChoices(choices, items: plan.cardOnly)
                    })) {
                    ForEach(group.actions) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.leading, indent)
        .help(item.path)
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
        }
    }

    /// An album's pop-up: its songs' shared choice, or "Mixed".
    private func albumPicker(_ album: CardOnlyAlbum, group: CardOnlyGroup) -> some View {
        let choices = sync.options.cardOnlyChoices
        let actions = Set(album.items.map(choices.action(for:)))
        let current = actions.count == 1 ? actions.first : nil
        return Picker("Album action", selection: Binding<CardOnlyAction?>(
            get: { current },
            set: { action in
                guard let action else { return }
                var choices = sync.options.cardOnlyChoices
                for item in album.items { choices.perFile[item.path] = action }
                sync.options.setCardOnlyChoices(choices, items: plan.cardOnly)
            })) {
            if current == nil { Text("Mixed").tag(CardOnlyAction?.none) }
            ForEach(group.actions) { Text($0.title).tag(CardOnlyAction?.some($0)) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func sizeText(_ size: UInt64) -> some View {
        Text(Int64(size).formatted(ByteCountFormatStyle(style: .file)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    // MARK: Collapsing

    /// Open/closed state for a section. While filtering, every section is
    /// open so matches are never hidden.
    private func isExpanded(_ id: String, count: Int, alwaysOpen: Bool = false) -> Binding<Bool> {
        Binding(
            get: { isSearching || (expansion[id] ?? (alwaysOpen || count <= Self.collapseThreshold)) },
            set: { expansion[id] = $0 })
    }

    /// A section header that opens and closes its section, e.g. "Add (9,214)"
    /// or, while filtering, "Add (12 of 9,214)".
    private func sectionHeader(_ title: String, shown: Int, total: Int, expanded: Binding<Bool>) -> some View {
        let count = shown == total ? total.formatted() : "\(shown.formatted()) of \(total.formatted())"
        return Button {
            withAnimation(.snappy) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                Text("\(title) (\(count))")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSearching)
        .help(expanded.wrappedValue ? "Hide this list" : "Show this list")
    }

    /// The item rows when open; a "Show all" link when closed.
    @ViewBuilder
    private func collapsibleRows<Item: Identifiable, Row: View>(_ items: [Item], expanded: Binding<Bool>,
                                                                 @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        if expanded.wrappedValue {
            ForEach(items) { row($0) }
        } else if !items.isEmpty {
            Button("Show all \(items.count.formatted())") {
                withAnimation(.snappy) { expanded.wrappedValue = true }
            }
            .buttonStyle(.link)
        }
    }

    /// A collapsible list section, shown only when it has items.
    @ViewBuilder
    private func collapsibleSection<Item: Identifiable, Row: View>(_ id: String, _ title: String, _ items: [Item],
                                                                    alwaysOpen: Bool = false, footer: String? = nil,
                                                                    @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        if !items.isEmpty {
            let expanded = isExpanded(id, count: items.count, alwaysOpen: alwaysOpen)
            Section {
                collapsibleRows(items, expanded: expanded, row: row)
                if let footer, expanded.wrappedValue { note(footer) }
            } header: {
                sectionHeader(title, shown: items.count, total: items.count, expanded: expanded)
            }
        }
    }

    /// Playlist files to write and remove, with any limits or renames.
    @ViewBuilder
    private func playlistSection(writes: [PlannedPlaylist], removals: [PlaylistRemoval]) -> some View {
        let playlists = plan.playlistPlan
        if !playlists.writes.isEmpty || !playlists.overLimit.isEmpty {
            Section {
                ForEach(writes) { planned in
                    row(planned.playlist.name,
                        detail: planned.nameWasChanged ? "Saved as “\(planned.nameOnDevice)” (shortened or renamed for the Q2)"
                                                       : planned.path,
                        symbol: "music.note.list", color: .pink)
                }
                if !playlists.overLimit.isEmpty {
                    Label("The Q2 holds up to \(preview.profile.maximumPlaylists) playlists. These \(playlists.overLimit.count) won't be written: "
                          + playlists.overLimit.map(\.name).joined(separator: ", "),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if playlists.otherPlaylistFiles > 0 {
                    Label("The playlist folder also has \(playlists.otherPlaylistFiles) playlist files Q2 Sync didn't write. The Q2 imports those too, and they're left untouched.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                note("On the Q2, choose Library → Playlists → Import to bring these in. Songs that aren't on the card (for example, cloud-only songs) are left out of playlists.")
            } header: {
                Text("Playlists (\(playlists.writes.count))")
            }
        }
        if !playlists.removals.isEmpty {
            Section {
                ForEach(removals) { removal in
                    row((removal.path as NSString).lastPathComponent,
                        detail: "No longer selected: its file is removed from the card",
                        symbol: "minus.circle", color: .red)
                }
                note("Removing a playlist's file doesn't remove a playlist you already imported; delete that on the Q2.")
            } header: {
                Text("Remove Playlists (\(playlists.removals.count))")
            }
        }
    }

    /// An explanation at the end of a section. A list row, not a section
    /// footer: macOS cuts footers off at one line.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            if isUpToDate {
                // Nothing to apply: one button that just closes.
                Button("Done") { sync.close() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { sync.close() }
                    .keyboardShortcut(.cancelAction)
            }
            if !isUpToDate {
                Button(cardOnlyDeleteCount > 0 ? "Sync (Deletes \(cardOnlyDeleteCount.formatted()))" : "Sync") {
                    continueApplying()
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!assessment.canApply || (plan.isEmpty && !hasCardOnlyWork))
            }
        }
    }
}

/// A cover removal, made `Identifiable` for the preview list.
private struct CoverRemovalRow: Identifiable {
    let path: CardPath
    var id: CardPath { path }
}

// MARK: - Progress

/// Progress bar, current item and Cancel.
struct SyncProgressView: View {

    let sync: SyncCoordinator

    var body: some View {
        let progress = sync.progress
        VStack(alignment: .leading, spacing: 12) {
            // The album-cover step comes after the music and has its own
            // bar and estimate, so the bar doesn't sit full while it runs.
            Text(progress.isAddingCovers ? "Adding Album Covers…" : "Syncing…").font(.title2.bold())
            ProgressView(value: progress.fractionComplete)
            Text(sync.secondsRemaining.map(TimeRemainingEstimator.describe)
                 ?? (progress.totalBytes > 0 || progress.isAddingCovers ? "Estimating time remaining…" : " "))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(progress.currentItem.isEmpty ? "Starting…" : progress.currentItem)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail(progress))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack {
                Text("Don't disconnect the Q2 while syncing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { sync.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// e.g. "1.2 GB of 8.4 GB · 120 of 431 items", or "Cover 120 of 950"
    /// during the album-cover step.
    private func detail(_ progress: SyncProgress) -> String {
        if progress.isAddingCovers {
            return "Cover \(min(progress.coversDone + 1, progress.coversTotal).formatted()) of \(progress.coversTotal.formatted())"
        }
        let style = ByteCountFormatStyle(style: .file)
        var parts: [String] = []
        if progress.totalBytes > 0 {
            parts.append("\(Int64(progress.bytesCopied).formatted(style)) of \(Int64(progress.totalBytes).formatted(style))")
        }
        if progress.totalOperations > 0 {
            parts.append("\(progress.completedOperations.formatted()) of \(progress.totalOperations.formatted()) items")
        }
        // Covers come after the music; say so, as the estimate above is
        // for the music only until they start.
        if progress.coversTotal > 0 && progress.totalBytes > 0 {
            parts.append("then \(progress.coversTotal.formatted()) album covers")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Result

/// The outcome, with the "update your Q2's library" reminder.
struct SyncResultView: View {

    let report: SyncReport
    let profile: DeviceProfile
    let sync: SyncCoordinator
    let devices: DeviceMonitor

    /// For Verify Card.
    @Environment(AutoSyncController.self) private var autoSync

    /// Errors listed on screen; the rest are in the log.
    private static let maxErrorsShown = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if report.succeeded {
                Label("Sync Complete", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
            } else if report.wasCancelled {
                Label("Sync Cancelled", systemImage: "stop.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
            } else {
                Label("Sync Finished with Problems", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
            }

            Text(summary)

            if let reason = report.abortReason {
                Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !report.errors.isEmpty {
                // Capped and lazy: a failed sync of thousands of songs can
                // produce thousands of errors; the log has all of them.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(report.errors.prefix(Self.maxErrorsShown).enumerated()), id: \.offset) {
                            Text($0.element).font(.caption)
                        }
                        if report.errors.count > Self.maxErrorsShown {
                            Text("and \((report.errors.count - Self.maxErrorsShown).formatted()) more — see the log")
                                .font(.caption.italic())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            if coversChanged && !profile.coverRefreshSteps.isEmpty && !sync.didEject {
                Label("Album covers changed. After ejecting, refresh Cover Flow on the Q2 (the steps show once the card is ejected).",
                      systemImage: "photo.on.rectangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if report.succeeded && !sync.didEject {
                Text("Eject the card now? You can also verify every song on it first, or keep it connected to sync again.")
                    .fixedSize(horizontal: false, vertical: true)
                    .fontWeight(.medium)
            } else if report.succeeded {
                Text("The card has been ejected. Next, on your Q2:")
                    .fontWeight(.medium)
                let steps = profile.libraryUpdateSteps + (coversChanged ? profile.coverRefreshSteps : [])
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("The card is still connected. Fix the problems above and sync again; songs already copied won't be copied twice.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let log = report.logURL {
                    Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                }
                Spacer()
                if report.succeeded && !sync.didEject {
                    Button("Not Now") { sync.close() }
                        .keyboardShortcut(.cancelAction)
                    Button("Verify Card…") {
                        // The Verify Card sheet opens once this one closes
                        // (RootView shows it only while no sync sheet is up).
                        autoSync.verifier.present()
                        sync.close()
                    }
                    .disabled(sync.isEjecting)
                    .help("Compare every song on the card with your Mac's copy and fix damaged ones")
                    Button("Eject") { Task { await sync.ejectAfterSync(devices: devices) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(sync.isEjecting)
                } else {
                    Button("Done") { sync.close() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    /// `true` if this sync added or removed album covers, so Cover Flow
    /// needs refreshing on the Q2.
    private var coversChanged: Bool { report.coversWritten + report.coversRemoved > 0 }

    /// e.g. "Added 12, updated 1, removed 0 · 84.3 MB in 0:42".
    private var summary: String {
        var parts = ["Added \(report.added)", "updated \(report.updated)"]
        if report.moved > 0 { parts.append("renamed \(report.moved)") }
        if report.removed > 0 { parts.append("removed \(report.removed)") }
        if report.adopted > 0 { parts.append("recorded \(report.adopted) already on the card") }
        if report.cardOnlyMovedToMac > 0 { parts.append("\(report.cardOnlyMovedToMac) moved to your Mac") }
        if report.cardOnlyRemoved > 0 { parts.append("\(report.cardOnlyRemoved) card-only files deleted") }
        if report.playlistsWritten > 0 { parts.append("\(report.playlistsWritten) playlists written") }
        if report.playlistsRemoved > 0 { parts.append("\(report.playlistsRemoved) playlists removed") }
        if report.playlistsToImport > 0 {
            parts.append("\(report.playlistsToImport) playlists ready to import on the Q2")
        } else if report.playlistsTakenOut > 0 {
            parts.append("no playlists need importing")
        }
        if report.coversWritten > 0 { parts.append("\(report.coversWritten) album covers added") }
        let copied = report.bytesCopied == 0
            ? "nothing copied"
            : "\(Int64(report.bytesCopied).formatted(ByteCountFormatStyle(style: .file))) copied"
        return parts.joined(separator: ", ") + " · \(copied)"
    }
}
