//
//  CardFormatTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Checks the card format advice (Master Boot Record, one volume filling
//  the card): when it warns, and when it stays quiet.
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
    func unknownScheme() {
        #expect(CardFormatAdvice.check(scheme: nil) == nil)
    }

    @Test("A GUID scheme or no partition table warns")
    func warns() throws {
        let guid = try #require(CardFormatAdvice.check(scheme: .guid))
        #expect(guid.problem.contains("GUID Partition Map"))
        let bare = try #require(CardFormatAdvice.check(scheme: PartitionScheme.none))
        #expect(bare.problem.contains("no partition table"))
    }

    @Test("A Raspberry Pi card (small boot volume plus a Linux partition) warns")
    func raspberryPi() throws {
        let pi = CardPartitions(scheme: .masterBootRecord, volumeBytes: 534_773_760,
                                cardBytes: 124_950_000_000, volumeName: "bootfs",
                                otherPartitionBytes: [124_400_000_000])
        let advice = try #require(CardFormatAdvice.check(layout: pi))
        #expect(advice.problem.contains("Raspberry Pi"))
        #expect(advice.problem.contains("another partition"))
        #expect(advice.summary == "Most of this card can't be used")
    }

    @Test("Any other partition warns, however small, and doesn't name a Pi")
    func smallOtherPartition() throws {
        let card = CardPartitions(scheme: .masterBootRecord, volumeBytes: 125_900_000_000,
                                  cardBytes: 128_000_000_000, volumeName: "MUSIC",
                                  otherPartitionBytes: [2_000_000_000])
        let advice = try #require(CardFormatAdvice.check(layout: card))
        #expect(advice.problem.contains("another partition"))
        #expect(!advice.problem.contains("Raspberry Pi"))
        #expect(advice.summary == "Part of this card can't be used")
    }

    @Test("Two other partitions are counted")
    func twoOthers() throws {
        let card = CardPartitions(scheme: .masterBootRecord, volumeBytes: 40_000_000_000,
                                  cardBytes: 128_000_000_000, volumeName: "CAM",
                                  otherPartitionBytes: [40_000_000_000, 48_000_000_000])
        #expect(try #require(CardFormatAdvice.check(layout: card)).problem.contains("2 other partitions"))
    }

    @Test("A lone volume that doesn't fill the card warns about unused space")
    func unusedSpace() throws {
        let card = CardPartitions(scheme: .masterBootRecord, volumeBytes: 100_000_000_000,
                                  cardBytes: 128_000_000_000, volumeName: "Q2",
                                  otherPartitionBytes: [])
        #expect(try #require(CardFormatAdvice.check(layout: card)).problem.contains("doesn't fill the card"))
    }

    @Test("A volume filling an MBR card stays quiet, even a small card's alignment gap")
    func fullVolume() {
        let big = CardPartitions(scheme: .masterBootRecord, volumeBytes: 255_850_000_000,
                                 cardBytes: 255_860_000_000, volumeName: "Shanling-Q2", otherPartitionBytes: [])
        #expect(CardFormatAdvice.check(layout: big) == nil)
        let small = CardPartitions(scheme: .masterBootRecord, volumeBytes: 1_990_000_000,
                                   cardBytes: 2_006_000_000, volumeName: "Q2", otherPartitionBytes: [])
        #expect(CardFormatAdvice.check(layout: small) == nil)
    }

    @Test("A non-MBR scheme is reported first, even with other partitions")
    func schemeFirst() throws {
        let guid = CardPartitions(scheme: .guid, volumeBytes: 255_650_000_000, cardBytes: 255_860_000_000,
                                  volumeName: "Q2", otherPartitionBytes: [209_715_200])
        #expect(try #require(CardFormatAdvice.check(layout: guid)).summary == "This card isn't on Master Boot Record")
    }

    @Test("Unknown sizes and partitions, or no layout, never warn about space")
    func unknown() {
        #expect(CardFormatAdvice.check(layout: nil) == nil)
        let card = CardPartitions(scheme: .masterBootRecord, volumeBytes: nil, cardBytes: 128_000_000_000,
                                  volumeName: "boot", otherPartitionBytes: nil)
        #expect(CardFormatAdvice.check(layout: card) == nil)
    }
}
