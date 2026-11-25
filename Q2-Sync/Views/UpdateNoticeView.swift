//
//  UpdateNoticeView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  What the update window says: a new version, with a link to download it;
//  you're up to date; or the check didn't work.
//
//  HOW IT FITS
//  Shown by `AppUpdateModel` in an `UpdateWindow`.
//

import SwiftUI

/// The answer to a check for new versions.
enum UpdateNotice {
    case available(AppRelease)
    case upToDate
    /// The check failed, with the reason.
    case failed(String)
}

/// The update window's contents.
struct UpdateNoticeView: View {

    let notice: UpdateNotice
    /// This app's version.
    let currentVersion: String
    /// Opens the new version's download page.
    let download: () -> Void
    /// Stops the automatic checks offering this release.
    let skip: (AppRelease) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(message).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if case .available(let release) = notice {
                    Button("Skip This Version") { skip(release) }
                    Spacer()
                    Button("Later", action: close)
                        .keyboardShortcut(.cancelAction)
                    Button("View on GitHub", action: download)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Spacer()
                    Button("OK", action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var title: String {
        switch notice {
        case .available(let release): "Q2 Sync \(release.version) Is Available"
        case .upToDate: "Q2 Sync Is Up to Date"
        case .failed: "Couldn't Check for Updates"
        }
    }

    private var message: String {
        switch notice {
        case .available:
            "You have version \(currentVersion). Download the new one from GitHub, quit Q2 Sync, "
                + "then replace it in your Applications folder."
        case .upToDate: "There's no release newer than version \(currentVersion)."
        case .failed(let reason): reason
        }
    }
}

#Preview {
    UpdateNoticeView(notice: .available(AppRelease(tag: "v0.3.0")), currentVersion: "0.2",
                     download: {}, skip: { _ in }, close: {})
}
