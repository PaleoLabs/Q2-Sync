//
//  CardConnection.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Tells whether a card is connected THROUGH THE Q2 (USB cable, the Q2 in
//  USB Storage mode) or some other way (a card reader, the Mac's SD slot,
//  a USB stick), from what the drive reports about itself.
//
//  HOW IT'S USED
//  • Only a drive that looks like a Q2 pops up the "Is this your Q2?"
//    sheet. Other drives are listed quietly in the sidebar with "Set Up…",
//    so a camera card or USB stick doesn't nag.
//  • The firmware installer's last steps differ: "unplug the Q2" versus
//    "put the card back in your Q2".
//  It is a HINT, never a safety check: a card is still recognised only by
//  its volume UUID, which the user confirmed once (see `DeviceStore`).
//
//  WHAT A Q2 REPORTS (read 2026-11-21 from a Q2 on stock V1.36)
//  The Q2 is a Linux device on an Ingenic chip. In USB Storage mode it uses
//  Linux's standard "mass storage gadget":
//    • USB vendor / product ID 0x0525 / 0xa4a5 (Linux's default gadget IDs)
//    • USB manufacturer "ingenic", product "composite-storage"
//    • disk vendor "Linux", model "File-Stor Gadget"
//  Q2 Pod ships Shanling's kernel unchanged (its docs say so, and both
//  firmware files carry the same kernel checksum), so it reports the same.
//  That also means firmware can't be told apart this way.
//  Other Linux players on Ingenic chips may report the same, so the UI says
//  "looks like a Q2", and the user still confirms.
//

import Foundation

/// What a connected drive says about its hardware. Every field is optional:
/// macOS doesn't report all of them for every kind of drive.
struct DriveIdentity: Equatable, Sendable {
    /// USB vendor ID, e.g. 0x0525.
    var usbVendorID: Int?
    /// USB product ID, e.g. 0xa4a5.
    var usbProductID: Int?
    /// USB manufacturer string, e.g. "ingenic".
    var usbManufacturer: String?
    /// USB product string, e.g. "composite-storage".
    var usbProduct: String?
    /// The disk's vendor (from the storage protocol), e.g. "Linux".
    var diskVendor: String?
    /// The disk's model, e.g. "File-Stor Gadget".
    var diskModel: String?
    /// How the disk is attached, e.g. "USB", "Secure Digital".
    var busProtocol: String?
}

/// How a card is connected to the Mac.
enum CardConnection: String, Equatable, Sendable {
    /// Through the Q2 itself, by USB cable.
    case q2
    /// Some other way: a card reader, the Mac's SD slot, a USB drive.
    case otherDrive
    /// The drive's details couldn't be read.
    case unknown

    /// Decides from what the drive reports.
    ///
    /// A Q2 needs BOTH the Ingenic manufacturer AND Linux's storage-gadget
    /// IDs or disk names, so neither a random Linux gadget nor a random
    /// Ingenic device counts on its own.
    ///
    /// - Parameter identity: What macOS reported, or `nil` if nothing.
    /// - Returns: The connection.
    static func classify(_ identity: DriveIdentity?) -> CardConnection {
        guard let identity else { return .unknown }
        let isIngenic = identity.usbManufacturer?.trimmed.lowercased() == "ingenic"
        let hasGadgetIDs = identity.usbVendorID == 0x0525 && identity.usbProductID == 0xa4a5
        let hasGadgetDisk = identity.diskVendor?.trimmed == "Linux"
            && identity.diskModel?.trimmed == "File-Stor Gadget"
        if isIngenic && (hasGadgetIDs || hasGadgetDisk) { return .q2 }
        let knowsAnything = [identity.usbManufacturer, identity.diskVendor, identity.diskModel, identity.busProtocol]
            .contains { $0 != nil } || identity.usbVendorID != nil
        return knowsAnything ? .otherDrive : .unknown
    }

    /// Short text for the UI, e.g. in the device header.
    var label: String {
        switch self {
        case .q2: return "Connected by USB"
        case .otherDrive: return "In a card reader"
        case .unknown: return "Connected"
        }
    }

    /// `true` if the "Is this your Q2?" sheet should pop up for a new drive
    /// on this connection. Unknown drives still ask, as before.
    var promptsForSetUp: Bool { self != .otherDrive }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
