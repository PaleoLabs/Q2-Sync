//
//  CardFormat.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Decides whether a card's layout suits the Q2: one FAT volume filling a
//  Master Boot Record (MBR) card. Shanling supports exFAT and FAT32 (and
//  NTFS, which macOS can't write), so either FAT format is fine here;
//  `VolumeEligibility` already refuses anything else. A card that isn't
//  MBR, has any other partition (a card reused from a Raspberry Pi: a
//  small boot partition plus a Linux one), or leaves part of the card
//  unused only gets a warning, with steps to erase it in Disk Utility; Q2 Sync never
//  formats a card itself.
//
//  HOW IT FITS
//  `DriveIdentityReader.cardLayout` (App) reads the scheme and sizes from
//  Disk Arbitration into a `CardPartitions` here. `DeviceMonitor` keeps it per
//  mounted card; the new-card sheet and the device page show
//  `CardFormatAdvice`.
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

/// What a card reader shows of a card: its partition scheme, how much of
/// the card the mounted volume takes up, and any other partitions.
struct CardPartitions: Equatable, Sendable {
    /// How the card is partitioned.
    let scheme: PartitionScheme
    /// The mounted volume's size in bytes, if known.
    let volumeBytes: Int64?
    /// The whole card's size in bytes, if known.
    let cardBytes: Int64?
    /// The volume's name, e.g. "bootfs" (hints at a Raspberry Pi card).
    let volumeName: String
    /// The sizes of the card's other partitions (any format, mounted or
    /// not), or `nil` if they couldn't be read.
    let otherPartitionBytes: [Int64]?

    /// The volume should cover at least this share of the card. A normal
    /// card loses only its alignment gap (1 to 16 MB: over 99%, even on a
    /// 2 GB card), so anything less leaves space the Q2 can't use.
    static let fullVolumeShare = 0.97

    /// The share of the card the volume covers, if known.
    var volumeShare: Double? {
        guard let volumeBytes, let cardBytes, volumeBytes > 0, cardBytes > 0 else { return nil }
        return Double(volumeBytes) / Double(cardBytes)
    }

    /// `true` if the card has a partition besides the volume.
    var hasOtherPartitions: Bool { !(otherPartitionBytes ?? []).isEmpty }

    /// `true` if the volume leaves part of the card unused.
    var volumeLeavesSpaceUnused: Bool {
        guard let volumeShare else { return false }
        return volumeShare < Self.fullVolumeShare
    }

    /// `true` if the volume is named like a Raspberry Pi (or other Linux
    /// computer's) boot partition.
    var looksLikeLinuxBootCard: Bool {
        ["bootfs", "boot"].contains(volumeName.lowercased())
    }
}

/// A suggestion to re-format the card, shown when it isn't one FAT volume
/// on Master Boot Record.
struct CardFormatAdvice: Equatable, Sendable {

    /// What's wrong, e.g. "This card uses the GUID Partition Map scheme…".
    let problem: String

    /// A short label for a link, e.g. "This card isn't on Master Boot Record".
    let summary: String

    /// What happens if the card is used as it is.
    let consequence: String

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
        return CardFormatAdvice(
            problem: "This card \(what). The Q2 expects a Master Boot Record partition table.",
            summary: "This card isn't on Master Boot Record",
            consequence: "Syncing still works, but the Q2 may not read the card reliably, or at all.")
    }

    /// Checks a card's whole layout: first its scheme (erasing to MBR
    /// fixes everything else too), then that the volume is the card's only
    /// partition (any other, of any format or size, is space the Q2 can't
    /// use, or a second volume it may not read), then that it fills the card.
    ///
    /// - Parameter layout: What the card reader shows, or `nil` if unknown.
    /// - Returns: Advice, or `nil` if the card looks right or is unknown.
    static func check(layout: CardPartitions?) -> CardFormatAdvice? {
        guard let layout else { return nil }
        if layout.scheme != .masterBootRecord { return check(scheme: layout.scheme) }
        guard layout.hasOtherPartitions || layout.volumeLeavesSpaceUnused else { return nil }

        let style = ByteCountFormatStyle(style: .file)
        let origin = layout.looksLikeLinuxBootCard
            ? "This looks like a card from a Raspberry Pi or another Linux computer. "
            : ""
        let summary = (layout.volumeShare ?? 1) < 0.5 ? "Most of this card can't be used" : "Part of this card can't be used"
        let usable = layout.volumeBytes.map { volume in
            layout.cardBytes.map { " Only \(volume.formatted(style)) of the card's \($0.formatted(style)) can hold music." } ?? ""
        } ?? ""

        let problem: String
        if let others = layout.otherPartitionBytes, !others.isEmpty {
            let total = others.reduce(0, +).formatted(style)
            let what = others.count == 1 ? "another partition (\(total))" : "\(others.count) other partitions (\(total) in all)"
            problem = "\(origin)This card has \(what) that the Q2 can't use.\(usable)"
        } else {
            problem = "\(origin)This volume doesn't fill the card: the rest is unused, and the Q2 can't use it.\(usable)"
        }
        return CardFormatAdvice(
            problem: problem,
            summary: summary,
            consequence: "Syncing still works, but only into this volume, and the Q2 may not read the card reliably.")
    }
}
