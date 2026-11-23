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
//  `cardLayout` reads the whole disk's partition table type and sizes the
//  same way, and counts its other partitions by walking DOWN the whole
//  disk's I/O Kit entry, for `CardFormatAdvice`.
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

    /// How the card behind a mounted volume is laid out: its partition
    /// scheme and the volume's and whole card's sizes.
    ///
    /// - Parameters:
    ///   - volumeURL: The volume's mount point.
    ///   - volumeName: The volume's name (for the Raspberry Pi hint).
    /// - Returns: The layout, or `nil` if the scheme can't be read.
    /// - Side effects: None (system lookups only).
    static func cardLayout(forVolumeAt volumeURL: URL, volumeName: String) -> CardPartitions? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL),
              let whole = DADiskCopyWholeDisk(disk) else {
            return nil
        }
        // A volume that IS the whole disk has no partition table.
        let volumeBSDName = DADiskGetBSDName(disk).map { String(cString: $0) }
        let wholeBSDName = DADiskGetBSDName(whole).map { String(cString: $0) }
        let wholeDescription = DADiskCopyDescription(whole) as? [CFString: Any]
        let volumeDescription = DADiskCopyDescription(disk) as? [CFString: Any]
        guard let scheme = PartitionScheme(
            mediaContent: wholeDescription?[kDADiskDescriptionMediaContentKey] as? String,
            volumeIsWholeDisk: volumeBSDName != nil && volumeBSDName == wholeBSDName) else {
            return nil
        }
        return CardPartitions(scheme: scheme,
                          volumeBytes: (volumeDescription?[kDADiskDescriptionMediaSizeKey] as? NSNumber)?.int64Value,
                          cardBytes: (wholeDescription?[kDADiskDescriptionMediaSizeKey] as? NSNumber)?.int64Value,
                          volumeName: volumeName,
                          otherPartitionBytes: otherPartitionSizes(of: whole, besides: volumeBSDName))
    }

    /// The sizes of the card's partitions other than the volume's own:
    /// every leaf `IOMedia` below the whole disk (whatever its format,
    /// mounted or not).
    ///
    /// - Parameters:
    ///   - whole: The whole disk.
    ///   - volumeBSDName: The volume's BSD name, e.g. "disk5s1", left out.
    /// - Returns: Each other partition's size in bytes, or `nil` if the
    ///   registry couldn't be read.
    private static func otherPartitionSizes(of whole: DADisk, besides volumeBSDName: String?) -> [Int64]? {
        let media = DADiskCopyIOMedia(whole)
        guard media != 0 else { return nil }
        defer { IOObjectRelease(media) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(media, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var sizes: [Int64] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            guard IOObjectConformsTo(entry, "IOMedia") != 0,
                  property(entry, "Whole") as? Bool == false,
                  property(entry, "Leaf") as? Bool == true,
                  property(entry, "BSD Name") as? String != volumeBSDName,
                  let size = (property(entry, "Size") as? NSNumber)?.int64Value else { continue }
            sizes.append(size)
        }
        return sizes
    }

    /// One property of an I/O Kit entry.
    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Finds a property on the entry or the nearest parent that has it.
    private static func searchParents(_ entry: io_registry_entry_t, key: String) -> Any? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
    }
}
