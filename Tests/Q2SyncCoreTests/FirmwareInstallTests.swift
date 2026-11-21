//
//  FirmwareInstallTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for putting firmware on the card: telling a Q2 from a card reader,
//  recognising firmware files, reading Shanling's zip, finding downloads,
//  and the path guard's narrow `update.tar` exception. No network access;
//  "cards" are temp folders (see `TestCard`).
//

import Compression
import Foundation
import Testing
@testable import Q2SyncCore

// MARK: - Helpers

/// A minimal GNU tar header block plus the info entry, as real Q2 firmware
/// files start (see `FirmwareImage`).
func makeFirmwareHead(model: String = "Shanling Q2", version: String = "V1.36",
                      firstEntry: String = "firmware_v20.info", magic: String = "ustar  \0") -> Data {
    let info = "\(model)\n\(version)\n9c13f508e0fc7ee6c2fa6c5a8e066675  recovery-update/xImage\n"
    var header = [UInt8](repeating: 0, count: 512)
    for (index, byte) in firstEntry.utf8.enumerated() { header[index] = byte }
    let size = String(info.utf8.count, radix: 8)
    let sizeField = String(repeating: "0", count: 11 - size.count) + size
    for (index, byte) in sizeField.utf8.enumerated() { header[124 + index] = byte }
    for (index, byte) in magic.utf8.enumerated() { header[257 + index] = byte }
    var body = [UInt8](info.utf8)
    body += [UInt8](repeating: 0, count: 512 - body.count % 512)
    return Data(header + body)
}

/// Writes a fake firmware file of a plausible size (sparse, so it's quick).
func makeFirmwareFile(in folder: URL, head: Data = makeFirmwareHead(), size: UInt64 = 20_971_520) throws -> URL {
    let url = folder.appending(path: "update.tar")
    try head.write(to: url)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: size)
    try handle.close()
    return url
}

/// Builds a zip in memory. Each entry is stored or deflated.
func makeZip(_ entries: [(name: String, data: Data, deflate: Bool)], corruptCRC: Bool = false) throws -> Data {
    var output = Data()
    var central = Data()
    func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) }) }
    for entry in entries {
        var crc = CRC32(); crc.update(entry.data)
        let crcValue = corruptCRC ? crc.value ^ 1 : crc.value
        var payload = entry.data
        if entry.deflate {
            var compressed = Data()
            let filter = try OutputFilter(.compress, using: .zlib) { if let d = $0 { compressed.append(d) } }
            try filter.write(entry.data)
            try filter.finalize()
            payload = compressed
        }
        let name = Data(entry.name.utf8)
        let offset = UInt32(output.count)
        let method = entry.deflate ? 8 : 0
        let sizes: [Data] = [le32(crcValue), le32(UInt32(payload.count)), le32(UInt32(entry.data.count))]
        let local: [Data] = [le32(0x0403_4b50), le16(20), le16(0), le16(method), le16(0), le16(0)]
            + sizes + [le16(name.count), le16(0), name, payload]
        let record: [Data] = [le32(0x0201_4b50), le16(20), le16(20), le16(0), le16(method), le16(0), le16(0)]
            + sizes + [le16(name.count), le16(0), le16(0), le16(0), le16(0), le32(0), le32(offset), name]
        output.append(contentsOf: local.reduce(Data(), +))
        central.append(contentsOf: record.reduce(Data(), +))
    }
    let centralOffset = UInt32(output.count)
    output += central
    let end: [Data] = [le32(0x0605_4b50), le16(0), le16(0), le16(entries.count), le16(entries.count),
                       le32(UInt32(central.count)), le32(centralOffset), le16(0)]
    output.append(contentsOf: end.reduce(Data(), +))
    return output
}

// MARK: - Connection

@Suite("Card connection")
struct CardConnectionTests {

    /// What a Q2 reported on 2026-11-21.
    let q2 = DriveIdentity(usbVendorID: 0x0525, usbProductID: 0xa4a5, usbManufacturer: "ingenic",
                           usbProduct: "composite-storage", diskVendor: "Linux", diskModel: "File-Stor Gadget",
                           busProtocol: "USB")

    @Test("A Q2 on a USB cable is recognised")
    func q2Recognised() {
        #expect(CardConnection.classify(q2) == .q2)
        // Even if only the disk names could be read.
        var partial = q2; partial.usbVendorID = nil; partial.usbProductID = nil
        #expect(CardConnection.classify(partial) == .q2)
    }

    @Test("Card readers and other Linux gadgets aren't a Q2")
    func others() {
        let reader = DriveIdentity(diskVendor: "OWC TB3", diskModel: "SD Card Reader", busProtocol: "USB")
        #expect(CardConnection.classify(reader) == .otherDrive)
        var otherGadget = q2; otherGadget.usbManufacturer = "Linux Foundation"
        #expect(CardConnection.classify(otherGadget) == .otherDrive)
        var ingenicOnly = DriveIdentity(); ingenicOnly.usbManufacturer = "ingenic"
        #expect(CardConnection.classify(ingenicOnly) == .otherDrive)
    }

    @Test("Unreadable drives are unknown and still prompt for set-up")
    func unknown() {
        #expect(CardConnection.classify(nil) == .unknown)
        #expect(CardConnection.classify(DriveIdentity()) == .unknown)
        #expect(CardConnection.unknown.promptsForSetUp)
        #expect(CardConnection.q2.promptsForSetUp)
        #expect(!CardConnection.otherDrive.promptsForSetUp)
    }
}

// MARK: - Firmware files

@Suite("Firmware files")
struct FirmwareImageTests {

    @Test("Versions tell stock from Q2 Pod", arguments: [
        ("V1.36", FirmwareKind.stock, "1.36"), ("V1.32", .stock, "1.32"),
        ("V1890", .q2Pod, "1.8.9"), ("V1850", .q2Pod, "1.8.5"), ("v1870", .q2Pod, "1.8.7"),
    ])
    func classify(line: String, kind: FirmwareKind, version: String) throws {
        let result = try #require(FirmwareImage.classify(versionLine: line))
        #expect(result.0 == kind)
        #expect(result.1 == version)
    }

    @Test("Unknown version lines are refused", arguments: ["", "1.36", "V", "Version 2", "V12", "V1.36 beta"])
    func classifyRejects(line: String) {
        #expect(FirmwareImage.classify(versionLine: line) == nil)
    }

    @Test("Reads the info entry of real-looking firmware")
    func readsInfo() throws {
        let stock = try FirmwareImage.readInfo(fromTarHead: makeFirmwareHead())
        #expect(stock.0 == .stock && stock.1 == "1.36")
        let pod = try FirmwareImage.readInfo(fromTarHead: makeFirmwareHead(version: "V1890"))
        #expect(pod.0 == .q2Pod && pod.1 == "1.8.9")
    }

    @Test("Refuses other players, non-tars and missing info")
    func refuses() {
        #expect(throws: FirmwareImageError.wrongModel("Shanling M0")) {
            try FirmwareImage.readInfo(fromTarHead: makeFirmwareHead(model: "Shanling M0"))
        }
        #expect(throws: FirmwareImageError.notATar) {
            try FirmwareImage.readInfo(fromTarHead: makeFirmwareHead(magic: "zzzzz"))
        }
        #expect(throws: FirmwareImageError.missingInfo) {
            try FirmwareImage.readInfo(fromTarHead: makeFirmwareHead(firstEntry: "recovery-update/"))
        }
        #expect(throws: FirmwareImageError.notATar) {
            try FirmwareImage.readInfo(fromTarHead: Data(repeating: 0, count: 100))
        }
    }

    @Test("Inspects a file and checks its size")
    func inspect() throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = try makeFirmwareFile(in: folder, head: makeFirmwareHead(version: "V1890"))
        let info = try FirmwareImage.inspect(file)
        #expect(info == FirmwareImageInfo(kind: .q2Pod, version: "1.8.9", size: 20_971_520))
        #expect(info.displayName == "Q2 Pod 1.8.9")

        let tiny = folder.appending(path: "tiny.tar")
        try makeFirmwareHead().write(to: tiny)
        #expect(throws: FirmwareImageError.self) { try FirmwareImage.inspect(tiny) }
    }

    @Test("SHA-256 matches a known value")
    func sha256() throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "abc")
        try Data("abc".utf8).write(to: file)
        #expect(try FirmwareImage.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

// MARK: - Zip

@Suite("Zip extraction")
struct ZipTests {

    @Test("CRC-32 matches the standard check value")
    func crc() {
        var crc = CRC32()
        crc.update(Data("1234".utf8)); crc.update(Data("56789".utf8))
        #expect(crc.value == 0xCBF4_3926)
    }

    @Test("Extracts update.tar from a folder in the zip, deflated or stored", arguments: [true, false])
    func extracts(deflate: Bool) throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let content = Data((0..<300_000).map { UInt8($0 % 251) })
        let zip = folder.appending(path: "fw.zip")
        try makeZip([("Q2 Firmware V1.36/", Data(), false),
                     ("__MACOSX/Q2 Firmware V1.36/._update.tar", Data("junk".utf8), false),
                     ("Q2 Firmware V1.36/update.tar", content, deflate)]).write(to: zip)
        let out = folder.appending(path: "update.tar")
        try ZipExtractor.extract(fileNamed: "update.tar", from: zip, to: out)
        #expect(try Data(contentsOf: out) == content)
    }

    @Test("A damaged entry is caught and leaves nothing behind")
    func damaged() throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let zip = folder.appending(path: "fw.zip")
        try makeZip([("update.tar", Data("hello".utf8), true)], corruptCRC: true).write(to: zip)
        let out = folder.appending(path: "update.tar")
        #expect(throws: ZipError.damaged) { try ZipExtractor.extract(fileNamed: "update.tar", from: zip, to: out) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test("Missing, doubled and non-zip files are refused")
    func refuses() throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let out = folder.appending(path: "out.tar")
        let none = folder.appending(path: "none.zip")
        try makeZip([("readme.txt", Data("x".utf8), false)]).write(to: none)
        #expect(throws: ZipError.entryNotFound("update.tar")) {
            try ZipExtractor.extract(fileNamed: "update.tar", from: none, to: out)
        }
        let two = folder.appending(path: "two.zip")
        try makeZip([("a/update.tar", Data("1".utf8), false), ("b/update.tar", Data("2".utf8), false)]).write(to: two)
        #expect(throws: ZipError.severalEntries("update.tar")) {
            try ZipExtractor.extract(fileNamed: "update.tar", from: two, to: out)
        }
        let notZip = folder.appending(path: "not.zip")
        try Data("plain text".utf8).write(to: notZip)
        #expect(throws: ZipError.notAZip) { try ZipExtractor.extract(fileNamed: "update.tar", from: notZip, to: out) }
    }
}

// MARK: - Sources

@Suite("Firmware sources")
struct FirmwareSourceTests {

    @Test("GitHub's update.tar and its digest are read")
    func gitHubAsset() throws {
        let json = """
        {"tag_name":"1.8.9","name":"1.8.9","draft":false,"prerelease":false,
         "html_url":"https://github.com/DiamondBond/q2-pod/releases/tag/1.8.9","body":"notes",
         "assets":[{"name":"Q2-Pod-User-Guide.pdf","size":1,"browser_download_url":"https://example.com/guide.pdf"},
                   {"name":"update.tar","size":54046720,
                    "browser_download_url":"https://github.com/DiamondBond/q2-pod/releases/download/1.8.9/update.tar",
                    "digest":"sha256:3841f8c42ae6add257624a9d433acf9aed79d5b053fef860f9692050a7687cf5"}]}
        """
        let release = try FirmwareRelease.parseGitHub(Data(json.utf8))
        let offer = try FirmwareSources.q2PodOffer(from: release)
        #expect(offer.kind == .q2Pod && offer.version == "1.8.9" && offer.packaging == .tar)
        #expect(offer.downloadURL.lastPathComponent == "update.tar")
        #expect(offer.expectedSize == 54_046_720)
        #expect(offer.expectedSHA256 == "3841f8c42ae6add257624a9d433acf9aed79d5b053fef860f9692050a7687cf5")
    }

    @Test("A release without update.tar has no offer")
    func noAsset() throws {
        let json = #"{"tag_name":"1.8.5","html_url":"https://example.com","assets":[]}"#
        #expect(throws: FirmwareSourceError.noUpdateFile) {
            try FirmwareSources.q2PodOffer(from: try FirmwareRelease.parseGitHub(Data(json.utf8)))
        }
    }

    @Test("Malformed digests are ignored")
    func digests() {
        #expect(FirmwareRelease.parseDigest(nil) == nil)
        #expect(FirmwareRelease.parseDigest("md5:abc") == nil)
        #expect(FirmwareRelease.parseDigest("sha256:1234") == nil)
        #expect(FirmwareRelease.parseDigest("SHA256:" + String(repeating: "A", count: 64)) == String(repeating: "a", count: 64))
    }

    @Test("Shanling's page gives the version and Drive link")
    func shanlingPage() throws {
        let html = """
        <div class="t">Version:</div><div>Shanling Q2 Firmware V1.36</div>
        <a href="https://drive.google.com/file/d/1HyST2-QkhUa6BdJP_ljBjkICxd-u8act/view?usp=drive_link" target="_self">Download</a>
        <a href="http://openwin.shanling.com:9000/pdf/sms/Q2v1.0.pdf">Manual</a>
        """
        let offer = try FirmwareSources.stockOffer(fromShanlingPage: html)
        #expect(offer.kind == .stock && offer.version == "1.36" && offer.packaging == .zip)
        #expect(offer.expectedSHA256 == nil)
        #expect(offer.downloadURL.absoluteString
                == "https://drive.usercontent.google.com/download?id=1HyST2-QkhUa6BdJP_ljBjkICxd-u8act&export=download&confirm=t")
    }

    @Test("A changed Shanling page is reported")
    func changedPage() {
        #expect(throws: FirmwareSourceError.shanlingPageChanged) {
            try FirmwareSources.stockOffer(fromShanlingPage: "<p>Shanling Q2 Firmware V1.36</p>")
        }
    }
}

// MARK: - Card

@Suite("Firmware on the card")
struct FirmwareCardTests {

    @Test("Only update.tar at the card root gets the exception")
    func guardException() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let url = try card.pathGuard.checkFirmwareUpdateFile(for: .write)
        #expect(url.lastPathComponent == "update.tar")
        #expect(url.deletingLastPathComponent().path == card.pathGuard.cardRoot.path)
        // Normal checks still refuse it, and Q2 Pod's own .part file.
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("update.tar", for: .write) }
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("update.tar.part", for: .delete) }
        #expect(throws: PathGuard.Violation.self) {
            try card.pathGuard.checkFirmwareUpdateFile(for: .deleteConfirmedByUser)
        }
    }

    @Test("A folder or symlink named update.tar is refused")
    func notAPlainFile() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let target = card.root.appending(path: "update.tar")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.checkFirmwareUpdateFile(for: .write) }
        try FileManager.default.removeItem(at: target)
        let elsewhere = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: elsewhere.appending(path: "x.tar"))
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.checkFirmwareUpdateFile(for: .write) }
    }

    @Test("The exception still needs the confirmed card")
    func wrongCard() throws {
        /// Flips once the guard exists, as if another card were inserted.
        final class Swap: @unchecked Sendable { var swapped = false }
        let swap = Swap()
        let card = try TestCard(); defer { card.cleanUp() }
        let pathGuard = try PathGuard(cardRoot: card.root, expectedVolumeUUID: TestCard.uuid, profile: .q2Pod,
                                      homeMusicFolder: fakeHomeMusic,
                                      volumeInfo: { _ in makeVolume(uuid: swap.swapped ? "OTHER" : TestCard.uuid) })
        _ = try pathGuard.checkFirmwareUpdateFile(for: .write)
        swap.swapped = true
        #expect(throws: PathGuard.Violation.self) { try pathGuard.checkFirmwareUpdateFile(for: .write) }
    }

    @Test("Placing copies, checks and renames into place; a bad checksum leaves nothing")
    func place() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: mac) }
        let file = try makeFirmwareFile(in: mac, size: 1_048_576)
        let sha = try FirmwareImage.sha256(of: file)

        #expect(throws: FirmwareImageError.checksumMismatch) {
            try card.fileSystem.placeFirmwareUpdate(from: file, expectedSHA256: String(repeating: "0", count: 64))
        }
        #expect(card.fileSystem.firmwareUpdateFileSize() == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: card.root.appending(path: ".q2sync/tmp").path)) ?? []
        #expect(leftovers.isEmpty)

        try card.fileSystem.placeFirmwareUpdate(from: file, expectedSHA256: sha)
        #expect(card.fileSystem.firmwareUpdateFileSize() == 1_048_576)
        #expect(try FirmwareImage.sha256(of: card.root.appending(path: "update.tar")) == sha)

        try card.fileSystem.removeFirmwareUpdate()
        #expect(card.fileSystem.firmwareUpdateFileSize() == nil)
    }

    @Test("Devices saved before pending installs existed still load")
    func oldDeviceRecords() throws {
        let json = #"{"volumeUUID":"X","name":"Q2","firmware":"stock","bookmarkData":"","addedDate":0,"hasCompletedFirstSync":true}"#
        let device = try JSONDecoder().decode(KnownDevice.self, from: Data(json.utf8))
        #expect(device.pendingFirmwareInstall == nil)
    }
}
