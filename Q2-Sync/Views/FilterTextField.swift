//
//  FilterTextField.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The small filter field above the lists on the Q2's content tabs
//  (Music, Audiobooks, and later kinds such as podcasts): a magnifying
//  glass, the text, and a clear button. Edit › Find (⌘F) puts the cursor
//  in it.
//
//  HOW IT FITS
//  Registers itself with `AppNavigation` as `field` while on screen, so
//  Find goes to the filter field on top.
//

import SwiftUI

struct FilterTextField: View {

    /// The typed text.
    @Binding var text: String

    /// The grey text shown while empty, e.g. "Filter Artists".
    let prompt: String

    /// Which field this is, for Edit › Find.
    let field: FilterField

    @Environment(AutoSyncController.self) private var autoSync
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .frame(maxWidth: 220)
        // Edit › Find (⌘F) puts the cursor in the filter.
        .onAppear { autoSync.navigation.filterAppeared(field) }
        .onDisappear { autoSync.navigation.filterDisappeared(field) }
        .onChange(of: autoSync.navigation.findRequests) {
            if autoSync.navigation.filterField == field { isFocused = true }
        }
    }
}
