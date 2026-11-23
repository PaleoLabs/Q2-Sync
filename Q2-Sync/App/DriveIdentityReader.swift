//
//  DriveIdentityReader.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Reads what a mounted drive reports about its hardware (USB IDs and
//  names, disk vendor and model), so `CardConnection` can tell a Q2 on a
//  USB cable from a card reader.
//
//  HOW IT WORKS
//  1. Disk Arbitration (the macOS service behind disk mounting) gives the
//     disk's description for the volume: vendor, model, protocol.
//  2. Its I/O Kit entry is then searched UPWARDS (towards the USB port) for
//     the first parent with USB properties (vendor/product ID and strings).
//  Both are read-only lookups of system information; nothing on the drive
//  is opened or read. Any failure simply gives `nil` (unknown connection).
//  `partitionScheme` reads the whole disk's partition table type the same
//  way, for `CardFormatAdvice`.
//

import DiskArbitration
import Foundation
import IOKit

/// Reads a volume's drive identity from macOS.
enum DriveIdentityReader {

    /// The drive behind a mounted volume.
    ///
    /// - Parameter volumeURL: The volume's mount point.
    /// - Returns: What macOS reports, or `nil` if it can't be read.
    /// - Side effects: None (system lookups only).
    static func identity(forVolumeAt volumeURL: URL) -> DriveIdentity? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL) else {
            return nil
        }
        var identity = DriveIdentity()
        if let description = DADiskCopyDescription(disk) as? [CFString: Any] {
            identity.diskVendor = description[kDADiskDescriptionDeviceVendorKey] as? String
            identity.diskModel = description[kDADiskDescriptionDeviceModelKey] as? String
            identity.busProtocol = description[kDADiskDescriptionDeviceProtocolKey] as? String
        }

        // `DADiskCopyIOMedia` hands us an I/O Kit object we must release.
        let media = DADiskCopyIOMedia(disk)
        if media != 0 {
            defer { IOObjectRelease(media) }
            identity.usbVendorID = searchParents(media, key: "idVendor") as? Int
            identity.usbProductID = searchParents(media, key: "idProduct") as? Int
            identity.usbManufacturer = (searchParents(media, key: "USB Vendor Name")
                                        ?? searchParents(media, key: "kUSBVendorString")) as? String
            identity.usbProduct = (searchParents(media, key: "USB Product Name")
                                   ?? searchParents(media, key: "kUSBProductString")) as? String
        }
        return identity
    }

    /// How the disk behind a mounted volume is partitioned.
    ///
    /// - Parameter volumeURL: The volume's mount point.
    /// - Returns: The scheme, or `nil` if it can't be read.
    /// - Side effects: None (system lookups only).
    static func partitionScheme(forVolumeAt volumeURL: URL) -> PartitionScheme? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL),
              let whole = DADiskCopyWholeDisk(disk) else {
            return nil
        }
        // A volume that IS the whole disk has no partition table.
        let volumeName = DADiskGetBSDName(disk).map { String(cString: $0) }
        let wholeName = DADiskGetBSDName(whole).map { String(cString: $0) }
        let description = DADiskCopyDescription(whole) as? [CFString: Any]
        return PartitionScheme(mediaContent: description?[kDADiskDescriptionMediaContentKey] as? String,
                               volumeIsWholeDisk: volumeName != nil && volumeName == wholeName)
    }

    /// Finds a property on the entry or the nearest parent that has it.
    private static func searchParents(_ entry: io_registry_entry_t, key: String) -> Any? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
    }
}
