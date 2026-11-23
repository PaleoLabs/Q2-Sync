//
//  CardFormat.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Decides whether a card's partition table suits the Q2: Master Boot
//  Record (MBR). Shanling supports exFAT and FAT32 (and NTFS, which macOS
//  can't write), so either FAT format is fine here; `VolumeEligibility`
//  already refuses anything else. A card that isn't MBR only gets a
//  warning, with steps to erase it in Disk Utility; Q2 Sync never formats
//  a card itself.
//
//  HOW IT FITS
//  `DriveIdentityReader.partitionScheme` (App) reads the scheme from Disk
//  Arbitration and turns it into a `PartitionScheme` here. `DeviceMonitor`
//  keeps it per mounted card, and the device page shows `CardFormatAdvice`.
//  Hard refusals (not FAT at all, not removable…) stay in
//  `VolumeEligibility`; this file never blocks anything.
//

import Foundation

/// How a card's disk is partitioned.
enum PartitionScheme: Equatable, Sendable {
    /// Master Boot Record (Disk Utility: "Master Boot Record").
    case masterBootRecord
    /// GUID Partition Map (Disk Utility: "GUID Partition Map").
    case guid
    /// Apple Partition Map (old Macs).
    case apple
    /// No partition table: the file system fills the whole disk.
    case none
    /// Something else macOS reported.
    case other(String)

    /// Maps Disk Arbitration's media content of the WHOLE disk.
    ///
    /// - Parameters:
    ///   - mediaContent: `kDADiskDescriptionMediaContentKey` of the whole
    ///     disk, e.g. `"FDisk_partition_scheme"`.
    ///   - volumeIsWholeDisk: `true` if the volume is the whole disk itself
    ///     (no partition table).
    /// - Returns: The scheme, or `nil` if nothing useful was reported.
    init?(mediaContent: String?, volumeIsWholeDisk: Bool) {
        if volumeIsWholeDisk { self = .none; return }
        switch mediaContent {
        case "FDisk_partition_scheme": self = .masterBootRecord
        case "GUID_partition_scheme":  self = .guid
        case "Apple_partition_scheme": self = .apple
        case let other?:
            guard !other.isEmpty else { return nil }
            self = .other(other)
        case nil:
            return nil
        }
    }

    /// The name Disk Utility uses.
    var displayName: String {
        switch self {
        case .masterBootRecord: return "Master Boot Record"
        case .guid:             return "GUID Partition Map"
        case .apple:            return "Apple Partition Map"
        case .none:             return "None (no partition table)"
        case .other(let name):  return name
        }
    }
}

/// A suggestion to re-format the card, shown when it isn't on MBR.
struct CardFormatAdvice: Equatable, Sendable {

    /// What's wrong, in one sentence, e.g. "This card uses GUID Partition Map."
    let problem: String

    /// The Disk Utility steps, in order.
    static let diskUtilitySteps = [
        "Copy anything you want to keep off the card first: erasing deletes everything on it.",
        "Open Disk Utility and choose View → Show All Devices.",
        "Select the card itself (the device above its volume), not the volume.",
        "Click Erase. Choose Format “ExFAT” (or “MS-DOS (FAT)”) and Scheme “Master Boot Record”, then click Erase.",
        "Reconnect the card. Q2 Sync will ask about it as a new card, then sync your music back.",
    ]

    /// Checks a card's partition scheme. The format (exFAT or FAT32) isn't
    /// judged: both suit the Q2.
    ///
    /// - Parameter scheme: The partition scheme, or `nil` if unknown.
    /// - Returns: Advice, or `nil` if the card is on MBR or the scheme
    ///   couldn't be read (unknown never warns: a wrong warning is worse).
    static func check(scheme: PartitionScheme?) -> CardFormatAdvice? {
        guard let scheme, scheme != .masterBootRecord else { return nil }
        let what = scheme == .none ? "has no partition table" : "uses the \(scheme.displayName) scheme"
        return CardFormatAdvice(problem: "This card \(what). The Q2 expects a Master Boot Record partition table.")
    }
}
