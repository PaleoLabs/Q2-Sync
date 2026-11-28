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

    /// Whether the cursor is in the filter field.
    @FocusState private var isSearchFocused: Bool

    /// For Edit › Find.
    @Environment(AutoSyncController.self) private var autoSync

    /// Sections the user opened or closed, by section ID. Untouched
    /// sections are open (see `isExpanded`).
    @State private var expansion: [String: Bool] = [:]

    /// Counts and lists, closed by default; remembered between syncs.
    @AppStorage("syncPreviewShowsDetails") private var showsDetails = false

    /// Card-only albums the user opened, by `CardOnlyAlbum.id`.
    @State private var expandedAlbums: Set<String> = []

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

    /// Everything you no longer sync that's still on the card, all kinds
    /// together (songs, audiobooks, podcast episodes). One Remove choice
    /// covers them all.
    private var noLongerSyncedCount: Int {
        plan.removals.count + plan.audiobooks.booksToRemove + plan.podcasts.removals.count
    }

    /// e.g. "47 songs, 2 audiobooks". Add new kinds of content here.
    private var noLongerSyncedList: String {
        var parts: [String] = []
        if !plan.removals.isEmpty { parts.append(pluralized(plan.removals.count, "song")) }
        if plan.audiobooks.booksToRemove > 0 { parts.append(pluralized(plan.audiobooks.booksToRemove, "audiobook")) }
        if !plan.podcasts.removals.isEmpty { parts.append(pluralized(plan.podcasts.removals.count, "podcast episode")) }
        return parts.joined(separator: ", ")
    }

    /// What Sync will take off the card with the current choices: items
    /// you no longer sync (if Remove is ticked) and card-only files set
    /// to Delete. Shown on the Sync button.
    private var removeCountOnSync: Int {
        (sync.options.applyRemovals ? noLongerSyncedCount : 0) + cardOnlyDeleteCount
    }

    /// `true` if the user chose any action other than Leave for card-only files.
    private var hasCardOnlyWork: Bool {
        plan.cardOnly.contains { (sync.options.cardOnlyActions[$0.path] ?? .leave) != .leave }
    }

    /// Nothing to copy, rename, remove or decide.
    private var isUpToDate: Bool { plan.isEmpty && !hasCardOnlyWork }

    /// Up to date with no lists worth showing (nothing skipped, nothing
    /// only on the card), so the list area shows a centred message.
    /// "Only changed playlists" is on and playlists from an earlier sync
    /// are still in the import folder: ask whether they were imported,
    /// since Q2 Sync can't tell. Unticked, they stay.
    private var asksAboutPlaylistImport: Bool {
        plan.playlistPlan.onlyChangedForImport && !plan.playlistPlan.reimportAll
            && plan.playlistPlan.waitingForImport > 0
    }

    private var hasNothingToList: Bool {
        plan.isEmpty && plan.cardOnly.isEmpty && plan.skipped.isEmpty
            && plan.audiobooks.skipped.isEmpty && plan.audiobooks.note == nil
            && plan.podcasts.skipped.isEmpty && plan.podcasts.note == nil
    }

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
                    details
                }
            }
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 660, height: showsDetails && !hasNothingToList ? detailsHeight : nil)
        // Grows downward otherwise; keep it centred like when it opened.
        .keepsSheetCentered()
        // Edit › Find (⌘F) opens Details if needed and puts the cursor in
        // the filter.
        .onAppear { if !hasNothingToList { autoSync.navigation.filterAppeared(.syncPreview) } }
        .onDisappear { autoSync.navigation.filterDisappeared(.syncPreview) }
        .onChange(of: autoSync.navigation.findRequests) {
            guard !hasNothingToList else { return }
            withAnimation(.snappy) { showsDetails = true }
            Task {
                // A field that was just added can't take the cursor yet.
                try? await Task.sleep(for: .milliseconds(100))
                isSearchFocused = true
            }
        }
        .confirmationDialog("Permanently delete \(pluralized(cardOnlyDeleteCount, "file")) from the card?",
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

            // The list's filter sits at the right of the Details row
            // (only while Details is open) rather than on a row of its own,
            // so the list gets that height.
            HStack {
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
                Spacer()
                if showsDetails && !hasNothingToList {
                    searchField
                }
            }
        }
    }

    /// e.g. "This sync will update 3 playlists. Everything else you chose is
    /// already on the card. About 158.38 GB will be free on the card."
    ///
    /// Removals of what's no longer synced are left out whatever Remove
    /// It/Them says: the removal box and the Sync button already say so,
    /// and changing this sentence when the box is ticked could add a line
    /// and move the box under the pointer (#73).
    private var summaryText: String {
        var text = plan.summary(applyRemovals: false)
        if !isUpToDate {
            text += " About \(max(0, assessment.projectedFreeBytes).formatted(ByteCountFormatStyle(style: .file))) will be free on the card."
        }
        return text
    }

    /// Card-only groups that have files, in their usual order.
    private var cardOnlyGroups: [CardOnlyGroup] {
        CardOnlyGroup.allCases.filter { group in plan.cardOnly.contains { CardOnlyGroup($0) == group } }
    }

    /// What needs a choice. Removing what you no longer sync comes first,
    /// in its own tinted box (the only choice that deletes anything, so
    /// it must be hard to miss). Below it, a grey box for music only on
    /// the card (one pop-up per group) and playlists waiting in the import
    /// folder (only with "only changed playlists" on). Shown only when
    /// there's something to decide.
    @ViewBuilder
    private var decisions: some View {
        let hasOtherChoices = !cardOnlyGroups.isEmpty || asksAboutPlaylistImport
        if noLongerSyncedCount > 0 || hasOtherChoices {
            VStack(alignment: .leading, spacing: 8) {
                if noLongerSyncedCount > 0 {
                    removalChoice
                }
                if hasOtherChoices {
                    otherChoices
                    // The removal box says what will happen itself; this
                    // is for the pop-ups and the import checkbox.
                    Text("Nothing on the card changes unless you choose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One line and one checkbox for every kind of content you no longer
    /// sync (#65), tinted red when ticked and orange when not, with a line
    /// saying what will happen (#63).
    private var removalChoice: some View {
        let removing = sync.options.applyRemovals
        let tint: Color = removing ? .red : .orange
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "minus.circle")
                    .font(.title3)
                    .foregroundStyle(.red)
                Text("No longer synced, still on the card: \(noLongerSyncedList)")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Toggle(noLongerSyncedCount == 1 ? "Remove It" : "Remove Them",
                       isOn: Binding(get: { sync.options.applyRemovals },
                                     set: { sync.options.applyRemovals = $0 }))
                    .toggleStyle(.checkbox)
                    .fontWeight(.semibold)
                    .fixedSize()
            }
            Group {
                Text(removing
                     ? (noLongerSyncedCount == 1
                        ? "Will be deleted from the card. It stays in your library."
                        : "Will be deleted from the card. They stay in your library.")
                     : "Will stay on the card unless you tick \(noLongerSyncedCount == 1 ? "Remove It" : "Remove Them").")
                    .foregroundStyle(removing ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                if !plan.playlistPlan.removals.isEmpty {
                    Text("Playlists you no longer sync are removed either way; that never removes their songs.")
                        .foregroundStyle(.secondary)
                }
                if assessment.needsLargeRemovalConfirmation {
                    Label("That's \(removalPercent)% of the songs on this card. You'll be asked to confirm.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 26)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.55), lineWidth: 1))
    }

    /// Choices that don't remove what you no longer sync, in a grey box.
    private var otherChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            if asksAboutPlaylistImport {
                let waiting = plan.playlistPlan.waitingForImport
                HStack {
                    Image(systemName: "music.note.list").foregroundStyle(.pink)
                    Text(waiting == 1
                         ? "1 playlist from an earlier sync is still in the Q2's import folder."
                         : "\(waiting.formatted()) playlists from an earlier sync are still in the Q2's import folder.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Toggle("I imported them on the Q2", isOn: Binding(
                        get: { sync.options.playlistsWereImported },
                        set: { sync.options.playlistsWereImported = $0 }))
                        .toggleStyle(.checkbox)
                        .fixedSize()
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// One cell in a counts row: a number, or a dash when the action can't
    /// happen for that kind of content (e.g. renaming an album cover).
    private enum CountCell {
        case count(Int)
        /// Removals the user left off with Remove Them: the sync removes
        /// nothing, so the cell shows 0 (#78). The number is in the tooltip
        /// and in the line under the counts.
        case notRemoving(Int)
        case notApplicable
    }

    /// The five columns of the counts, in order.
    private static let countColumns: [(title: String, symbol: String, color: Color)] = [
        ("Add", "plus.circle.fill", .green),
        ("Update", "arrow.triangle.2.circlepath", .blue),
        ("Rename", "pencil.circle.fill", .purple),
        ("Remove", "minus.circle.fill", .red),
        ("Can't Sync", "exclamationmark.circle.fill", .orange),
    ]

    /// Width of the kind's name at the start of each counts row; the
    /// header leaves the same space so its words sit over the icons.
    private static let countNameWidth: CGFloat = 92

    /// The counts (#64, #78): a header row with the action names (Add,
    /// Update, Rename, Remove, Can't Sync), then one full-width grey row
    /// per kind of content that has something to do, each cell an icon and
    /// a number under its header. The counts say only what this sync will
    /// do: a zero is dimmed; a dash means the action doesn't apply. The
    /// sheet grows by one row per kind, never by action.
    private var counts: some View {
        let removing = sync.options.applyRemovals
        let playlists = plan.playlistPlan
        let books = plan.audiobooks
        let podcasts = plan.podcasts
        let newPlaylists = playlists.writes.filter(\.isNew).count

        let songCells: [CountCell] = [
            .count(addCount), .count(plan.copies.count - addCount), .count(plan.moves.count),
            removing || plan.removals.isEmpty ? .count(plan.removals.count) : .notRemoving(plan.removals.count),
            .count(plan.skipped.count),
        ]
        let bookCells: [CountCell] = [
            .count(books.booksToAdd), .count(books.booksToUpdate), .notApplicable,
            removing || books.booksToRemove == 0 ? .count(books.booksToRemove) : .notRemoving(books.booksToRemove),
            .count(books.skipped.count),
        ]
        let podcastCells: [CountCell] = [
            .count(podcasts.episodesToAdd), .count(podcasts.episodesToUpdate), .notApplicable,
            removing || podcasts.removals.isEmpty ? .count(podcasts.removals.count) : .notRemoving(podcasts.removals.count),
            .count(podcasts.skipped.count),
        ]
        let playlistCells: [CountCell] = [
            .count(newPlaylists), .count(playlists.writes.count - newPlaylists), .notApplicable,
            .count(playlists.removals.count), .count(playlists.overLimit.count),
        ]
        let coverCells: [CountCell] = [
            .count(plan.coverWrites.count), .notApplicable, .notApplicable,
            .count(plan.coverRemovals.count), .notApplicable,
        ]

        return VStack(alignment: .leading, spacing: 6) {
            if [songCells, bookCells, podcastCells, playlistCells, coverCells].contains(where: hasWork) { countHeader }
            if hasWork(songCells) { countRow("Songs", songCells) }
            if hasWork(bookCells) { countRow("Audiobooks", bookCells) }
            if hasWork(podcastCells) { countRow("Podcasts", podcastCells) }
            if hasWork(playlistCells) { countRow("Playlists", playlistCells) }
            if hasWork(coverCells) { countRow("Album Covers", coverCells) }
            // Sizes and free space are in the summary at the top, so
            // they're not repeated here.
            if let line = notCopiedSummary {
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    /// `true` if any cell has a number above zero.
    private func hasWork(_ cells: [CountCell]) -> Bool {
        cells.contains {
            switch $0 {
            case .count(let n): n > 0
            case .notRemoving, .notApplicable: false
            }
        }
    }

    /// The action names, once, above the counts rows (#78). Same layout as
    /// a row (name slot, spacing, padding), so each word starts over its
    /// column's icon. It sits closer to the first row than the rows sit to
    /// each other, so it reads as part of them. VoiceOver skips it: each
    /// row reads its actions by name.
    private var countHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.countNameWidth, height: 1)
            ForEach(Self.countColumns.indices, id: \.self) { index in
                Text(Self.countColumns[index].title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, -3)
        .accessibilityHidden(true)
    }

    /// One kind of content across the sheet: its name, then the five
    /// columns, each the same width in every row.
    private func countRow(_ title: String, _ cells: [CountCell]) -> some View {
        let columns = Self.countColumns
        return HStack(spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: Self.countNameWidth, alignment: .leading)
            ForEach(columns.indices, id: \.self) { index in
                countCell(title, columns[index].title, cells[index], columns[index].symbol, columns[index].color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ": " + columns.indices.map { spoken(columns[$0].title, cells[$0]) }
            .joined(separator: ", "))
    }

    /// Icon and number. Zero and dash are dimmed; the action's name is in
    /// the header.
    private func countCell(_ kind: String, _ title: String, _ cell: CountCell,
                           _ symbol: String, _ color: Color) -> some View {
        let value: String
        let dimmed: Bool
        switch cell {
        case .count(let n): (value, dimmed) = (n.formatted(), n == 0)
        case .notRemoving: (value, dimmed) = (0.formatted(), true)
        case .notApplicable: (value, dimmed) = ("–", true)
        }
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
            Text(value)
                .monospacedDigit()
                .fontWeight(dimmed ? .regular : .semibold)
                .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .help(helpText(kind, title, cell))
    }

    /// e.g. "Rename doesn't apply to audiobooks".
    private func helpText(_ kind: String, _ title: String, _ cell: CountCell) -> String {
        switch cell {
        case .count: ""
        case .notRemoving(let n):
            "\(n.formatted()) you no longer sync stay on the card because Remove Them is off"
        case .notApplicable: "\(title) doesn't apply to \(kind.lowercased())"
        }
    }

    /// What VoiceOver reads for one cell, e.g. "Add 34", "Rename doesn't apply".
    private func spoken(_ title: String, _ cell: CountCell) -> String {
        switch cell {
        case .count(let n): "\(title) \(n.formatted())"
        case .notRemoving(let n): "\(title) 0, \(n.formatted()) kept"
        case .notApplicable: "\(title) doesn't apply"
        }
    }

    /// e.g. "Already on the card: 1,203 songs, 4 audiobooks · 12 songs only
    /// on the card". `nil` when there's nothing to say.
    private var notCopiedSummary: String? {
        let books = plan.audiobooks
        var onCard: [String] = []
        let songs = plan.unchangedCount + plan.adoptions.count
        if songs > 0 { onCard.append(pluralized(songs, "song")) }
        let unchangedBooks = books.unchangedBooks + books.adoptions.count
        if unchangedBooks > 0 { onCard.append(pluralized(unchangedBooks, "audiobook")) }
        let unchangedEpisodes = plan.podcasts.unchangedEpisodes + plan.podcasts.alreadyOnCard
        if unchangedEpisodes > 0 { onCard.append(pluralized(unchangedEpisodes, "podcast episode")) }
        var parts: [String] = []
        if !onCard.isEmpty { parts.append("Already on the card: " + onCard.joined(separator: ", ")) }
        // Not removed because Remove Them is off (#78): the counts show 0.
        if !sync.options.applyRemovals && noLongerSyncedCount > 0 {
            let list = noLongerSyncedList.replacingOccurrences(of: ", ", with: " and ")
            parts.append("\(list) you no longer sync will stay")
        }
        if !plan.cardOnly.isEmpty { parts.append("\(pluralized(plan.cardOnly.count, "song")) only on the card") }
        let imported = sync.options.playlistsWereImported ? plan.playlistPlan.leavingImport.count : 0
        if imported > 0 { parts.append("\(pluralized(imported, "playlist")) already imported") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Sheet height with Details open: 725 pt, less on a short screen
    /// (never under 600) so the sheet stays inside the window it hangs from.
    private var detailsHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return min(725, max(600, screen - 140))
    }

    // MARK: Details

    private var addCount: Int { plan.copies.lazy.filter { $0.kind == .add }.count }

    /// A compact filter for the list (not the counts), at the right of the
    /// Details row.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter list", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .help("Filter the list by song, artist, album or path")
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
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(width: 200)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
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
    /// (songs, not copied, playlists, covers). All start open.
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
            collapsibleSection("skipped", "Can't Sync", lists.skipped) { track in
                row("\(track.displayArtist) — \(track.title)", detail: track.unavailableReason,
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
            audiobookSections
            podcastSections
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

    /// Audiobooks to copy, remove or that can't be synced, one row per book.
    @ViewBuilder
    private var audiobookSections: some View {
        let books = plan.audiobooks
        let copies = Dictionary(grouping: books.copies, by: \.bookID).values
            .compactMap(\.first).sorted { $0.bookTitle.localizedStandardCompare($1.bookTitle) == .orderedAscending }
        let removals = Dictionary(grouping: books.bookRemovals, by: \.bookID).values
            .compactMap(\.first).sorted { $0.bookTitle.localizedStandardCompare($1.bookTitle) == .orderedAscending }
        collapsibleSection("audiobookCopies", "Copy Audiobooks", copies,
                           footer: books.note) { copy in
            row(copy.bookTitle, detail: copy.folder, symbol: "book.closed", color: .green)
        }
        collapsibleSection("audiobookRemovals", "Remove Audiobooks", removals,
                           footer: "Removed only if you tick Remove Them. Only audiobooks Q2 Sync copied are removed.") { removal in
            row(removal.bookTitle, detail: (removal.path as NSString).deletingLastPathComponent,
                symbol: "minus.circle", color: .red)
        }
        collapsibleSection("audiobookSkipped", "Audiobooks That Can't Sync", books.skipped) { book in
            row(book.title, detail: book.availability.audiobookReason,
                symbol: book.availability.symbolName, color: .orange)
        }
        if copies.isEmpty, let text = books.note {
            Section { note(text) } header: { Text("Audiobooks") }
        }
    }

    /// Podcast episodes to copy, remove or that can't be synced, one row
    /// per episode, e.g. "The Daily — The Election".
    @ViewBuilder
    private var podcastSections: some View {
        let podcasts = plan.podcasts
        collapsibleSection("podcastCopies", "Copy Podcast Episodes", podcasts.copies,
                           footer: podcasts.note) { copy in
            row("\(copy.showTitle) — \(copy.title)", detail: copy.destination,
                symbol: copy.kind == .add ? "plus.circle" : "arrow.triangle.2.circlepath", color: .green)
        }
        collapsibleSection("podcastRemovals", "Remove Podcast Episodes", podcasts.removals,
                           footer: "Removed only if you tick Remove Them. Only episodes Q2 Sync copied are removed.") { removal in
            row("\(removal.showTitle) — \(removal.title)", detail: removal.reason.explanation,
                symbol: "minus.circle", color: .red)
        }
        collapsibleSection("podcastSkipped", "Podcast Episodes That Can't Sync", podcasts.skipped) { episode in
            row("\(episode.showTitle) — \(episode.title)", detail: episode.unsyncableReason ?? "",
                symbol: episode.isProtected ? "lock" : "video", color: .orange)
        }
        if podcasts.copies.isEmpty, let text = podcasts.note {
            Section { note(text) } header: { Text("Podcasts") }
        }
    }

    /// The songs to remove.
    @ViewBuilder
    private func removalSection(_ removals: [RemoveOperation]) -> some View {
        if !plan.removals.isEmpty {
            let expanded = isExpanded("remove")
            Section {
                // The one Remove Them checkbox (and the large-removal
                // warning) is in the box at the top; it isn't repeated here.
                collapsibleRows(removals, expanded: expanded) { removal in
                    row(removal.entry.title, detail: removal.entry.path, symbol: "minus.circle", color: .red)
                }
                note("Removed only if you tick Remove Them. Removed songs are deleted from the card; they're still in your library, so tick them again to put them back. Songs not put there by Q2 Sync are never removed here.")
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
            let expanded = isExpanded("cardOnly")
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
            : isExpanded("cardOnly.\(group.rawValue)")
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
                        Text("\(album.displayName) · \(pluralized(album.items.count, "song"))")
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

    /// Open/closed state for a section: open unless the user closed it
    /// (the lists are already behind Details, so long ones needn't start
    /// closed). While filtering, every section is open so matches show.
    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { isSearching || (expansion[id] ?? true) },
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
                                                                    footer: String? = nil,
                                                                    @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        if !items.isEmpty {
            let expanded = isExpanded(id)
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
                    Label("The Q2 holds up to \(preview.profile.maximumPlaylists) playlists. \(playlists.overLimit.count == 1 ? "This one" : "These \(playlists.overLimit.count)") won't be written: "
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
                Button(removeCountOnSync > 0 ? "Sync and Remove \(removeCountOnSync.formatted())" : "Sync") {
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
                 ?? (progress.totalBytes > 0 || progress.isAddingCovers || progress.isRemoving
                     ? "Estimating time remaining…" : " "))
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

    /// e.g. "1.2 GB of 8.4 GB · 120 of 431 items", "Removing 120 of 3,083
    /// · then 2.96 GB to copy" during the removal step, or "Cover 120 of
    /// 950" during the album-cover step.
    private func detail(_ progress: SyncProgress) -> String {
        if progress.isRemoving {
            var text = "Removing \(min(progress.removalsDone + 1, progress.removalsTotal).formatted()) of \(progress.removalsTotal.formatted())"
            // The estimate above is for the removals only; say what follows.
            if progress.totalBytes > 0 {
                text += " · then \(Int64(progress.totalBytes).formatted(ByteCountFormatStyle(style: .file))) to copy"
            }
            return text
        }
        if progress.isAddingCovers {
            return "Cover \(min(progress.coversDone + 1, progress.coversTotal).formatted()) of \(progress.coversTotal.formatted())"
        }
        let style = ByteCountFormatStyle(style: .file)
        var parts: [String] = []
        if progress.totalBytes > 0 {
            parts.append("\(Int64(progress.bytesCopied).formatted(style)) of \(Int64(progress.totalBytes).formatted(style))")
        }
        if progress.totalOperations > 0 {
            parts.append("\(progress.completedOperations.formatted()) of \(pluralized(progress.totalOperations, "item"))")
        }
        // Covers come after the music; say so, as the estimate above is
        // for the music only until they start.
        if progress.coversTotal > 0 && progress.totalBytes > 0 {
            parts.append("then \(pluralized(progress.coversTotal, "album cover"))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Result

/// The outcome and, after a successful sync, what to do next on the Q2.
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

            if report.succeeded {
                // Shown before ejecting, so they're seen however the card
                // is ejected.
                NumberedSteps(steps: profile.postSyncSteps(connection: sync.connection,
                                                           includePlaylists: report.playlistsToImport > 0,
                                                           includeCovers: coversChanged))
            } else {
                Text("The card is still connected. Fix the problems above and sync again; songs already copied won't be copied twice.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let log = report.logURL {
                Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                    .buttonStyle(.link)
                    .font(.callout)
            }

            HStack {
                if report.succeeded {
                    Button("Verify Card…") {
                        // The Verify Card sheet opens once this one closes
                        // (RootView shows it only while no sync sheet is up).
                        autoSync.verifier.present()
                        sync.close()
                    }
                    .disabled(!isCardConnected || sync.isEjecting)
                    .help("Compare every song on the card with your Mac's copy and fix damaged ones")
                    Spacer()
                    Button("Done") { sync.close() }
                        .keyboardShortcut(.cancelAction)
                    // Off if the card was already ejected another way (the
                    // menu bar, a notification, Finder).
                    Button("Eject") { Task { await sync.ejectAfterSync(devices: devices) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isCardConnected || sync.isEjecting)
                } else {
                    Spacer()
                    Button("Done") { sync.close() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    /// `true` while the card that was synced is still connected.
    private var isCardConnected: Bool {
        devices.connected != nil && devices.connected?.device.volumeUUID == sync.deviceUUID
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
        if report.cardOnlyRemoved > 0 { parts.append("\(pluralized(report.cardOnlyRemoved, "card-only file")) deleted") }
        if report.playlistsWritten > 0 { parts.append("\(pluralized(report.playlistsWritten, "playlist")) written") }
        if report.playlistsRemoved > 0 { parts.append("\(pluralized(report.playlistsRemoved, "playlist")) removed") }
        if report.playlistsToImport > 0 {
            parts.append("\(pluralized(report.playlistsToImport, "playlist")) ready to import on the Q2")
        } else if report.playlistsTakenOut > 0 {
            parts.append("no playlists need importing")
        }
        if report.coversWritten > 0 { parts.append("\(pluralized(report.coversWritten, "album cover")) added") }
        if report.audiobooksCopied > 0 { parts.append("\(pluralized(report.audiobooksCopied, "audiobook")) copied") }
        if report.audiobooksRemoved > 0 { parts.append("\(pluralized(report.audiobooksRemoved, "audiobook")) removed") }
        if report.podcastEpisodesCopied > 0 { parts.append("\(pluralized(report.podcastEpisodesCopied, "podcast episode")) copied") }
        if report.podcastEpisodesRemoved > 0 { parts.append("\(pluralized(report.podcastEpisodesRemoved, "podcast episode")) removed") }
        if !report.skippedPodcastEpisodes.isEmpty {
            parts.append("\(pluralized(report.skippedPodcastEpisodes.count, "podcast episode")) can't be synced (video or protected)")
        }
        let copied = report.bytesCopied == 0
            ? "nothing copied"
            : "\(Int64(report.bytesCopied).formatted(ByteCountFormatStyle(style: .file))) copied"
        return parts.joined(separator: ", ") + " · \(copied)"
    }
}

extension PodcastRemoval.Reason {

    /// Why the review sheet will remove an episode, in words.
    var explanation: String {
        switch self {
        case .notDownloaded: "No longer downloaded in Podcasts"
        case .showNotChosen: "Its show isn't chosen any more"
        case .played: "Played, and “Unplayed only” is on"
        case .podcastsOff: "Podcasts are turned off for this Q2"
        }
    }
}
