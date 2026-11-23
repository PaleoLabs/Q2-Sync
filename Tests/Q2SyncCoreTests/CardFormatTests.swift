//
//  CardFormatTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Checks the Master Boot Record advice: when it warns, and when it stays quiet.
//

import Testing
@testable import Q2SyncCore

@Suite("Card format advice")
struct CardFormatTests {

    @Test("Disk Arbitration's media content maps to a scheme")
    func schemes() {
        #expect(PartitionScheme(mediaContent: "FDisk_partition_scheme", volumeIsWholeDisk: false) == .masterBootRecord)
        #expect(PartitionScheme(mediaContent: "GUID_partition_scheme", volumeIsWholeDisk: false) == .guid)
        #expect(PartitionScheme(mediaContent: "Apple_partition_scheme", volumeIsWholeDisk: false) == .apple)
        #expect(PartitionScheme(mediaContent: "Windows_NTFS", volumeIsWholeDisk: true) == PartitionScheme.none)
        #expect(PartitionScheme(mediaContent: nil, volumeIsWholeDisk: false) == nil)
        #expect(PartitionScheme(mediaContent: "", volumeIsWholeDisk: false) == nil)
    }

    @Test("A Master Boot Record card gets no advice, whatever its FAT format")
    func good() {
        #expect(CardFormatAdvice.check(scheme: .masterBootRecord) == nil)
    }

    @Test("An unknown scheme never warns")
    func unknown() {
        #expect(CardFormatAdvice.check(scheme: nil) == nil)
    }

    @Test("A GUID scheme or no partition table warns")
    func warns() throws {
        let guid = try #require(CardFormatAdvice.check(scheme: .guid))
        #expect(guid.problem.contains("GUID Partition Map"))
        let bare = try #require(CardFormatAdvice.check(scheme: PartitionScheme.none))
        #expect(bare.problem.contains("no partition table"))
    }
}
