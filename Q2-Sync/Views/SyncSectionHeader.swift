//
//  SyncSectionHeader.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The top of every content tab on the Q2's page, laid out like Finder's
//  iPod page: a "Sync … onto [Q2]" checkbox on its own line, then a
//  right-aligned "Sync:" label with the choices stacked under each other,
//  then an optional note. Unticking the box dims the choices; each tab
//  dims its own list below too.
//
//  HOW IT FITS
//  Used by the Music and Audiobooks tabs, and meant for any later kind of
//  content (podcasts…), so every tab looks and behaves the same. The
//  bindings are edits through `DeviceMonitor.editSyncSettings`, saved
//  only on Apply.
//

import SwiftUI

/// One radio button under "Sync:".
struct SyncChoiceOption<Value: Hashable>: Identifiable {
    let label: String
    let value: Value
    var id: Value { value }
}

/// "Sync … onto [Q2]", then "Sync:" with stacked choices, then a note.
struct SyncSectionHeader<Value: Hashable, Note: View>: View {

    /// The checkbox's title, e.g. "Sync music onto Brian's Q2".
    let title: String

    /// The checkbox.
    @Binding var isEnabled: Bool

    /// The chosen radio button.
    @Binding var choice: Value

    /// The radio buttons, top to bottom.
    let options: [SyncChoiceOption<Value>]

    /// Shown under the choices (warnings, hints). Lay it out at a fixed
    /// place so the list below doesn't jump when it comes and goes.
    @ViewBuilder var note: () -> Note

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $isEnabled)
                .toggleStyle(.checkbox)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 0) {
                GridRow {
                    Text("Sync:")
                        .gridColumnAlignment(.trailing)
                    Picker("Sync", selection: $choice) {
                        ForEach(options) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }
            .padding(.leading, 22)
            .disabled(!isEnabled)

            note()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

extension SyncSectionHeader where Note == EmptyView {

    /// A header with no note.
    init(title: String, isEnabled: Binding<Bool>, choice: Binding<Value>, options: [SyncChoiceOption<Value>]) {
        self.init(title: title, isEnabled: isEnabled, choice: choice, options: options) { EmptyView() }
    }
}

/// A one-line hint or warning under a `SyncSectionHeader`.
struct SyncSectionNote: View {

    let text: String
    let systemImage: String
    /// Orange for warnings, the accent colour for a first step.
    var color: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(color)
            // Wraps to the width it's given. Not `fixedSize(vertical:)`:
            // that made the line ask for a huge minimum height when
            // measured narrow (#43).
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
