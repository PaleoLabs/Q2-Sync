//
//  PhotosAccess.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Permission to read the Photos library (issue #68). macOS asks once,
//  with its own privacy prompt; the answer is kept by macOS (System
//  Settings › Privacy & Security › Photos), not by Q2 Sync.
//
//  SAFETY
//  macOS only offers read-and-write access to Photos (`.readWrite`), but
//  Q2 Sync only reads: nothing in the app calls `performChanges`, so
//  nothing can be added to, changed in or deleted from the library.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`, one for all Q2s, like `PodcastsAccess`.
//  The Photos tab shows `status` and calls `allow()` (or
//  `openPrivacySettings()` once refused); `PhotoLibraryModel` reads the
//  library only while `status` is `.allowed`.
//

import AppKit
import Foundation
import Observation
import Photos

/// Whether Q2 Sync may read the Photos library.
@MainActor
@Observable
final class PhotosAccess {

    /// Where things stand.
    enum Status: Equatable {
        /// Never asked: the Allow button is shown.
        case notAllowed
        /// Allowed: every photo, or (`limited`) only the photos picked
        /// in macOS's prompt.
        case allowed(limited: Bool)
        /// Refused, or not allowed by a Mac's administrator. Only System
        /// Settings can change it.
        case denied
    }

    private(set) var status: Status = .notAllowed

    init() {
        refresh()
    }

    /// `true` while the library can be read.
    var isAllowed: Bool {
        if case .allowed = status { return true }
        return false
    }

    /// Reads the current answer from macOS (it can change in System
    /// Settings while Q2 Sync is open).
    func refresh() {
        status = Self.status(for: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// Shows macOS's privacy prompt (only the first time; afterwards it
    /// returns the earlier answer straight away).
    func allow() async {
        let answer = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = Self.status(for: answer)
    }

    /// Opens System Settings › Privacy & Security › Photos.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func status(for authorization: PHAuthorizationStatus) -> Status {
        switch authorization {
        case .authorized: .allowed(limited: false)
        case .limited: .allowed(limited: true)
        case .denied, .restricted: .denied
        case .notDetermined: .notAllowed
        @unknown default: .denied
        }
    }
}
