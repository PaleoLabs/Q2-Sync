//
//  FirmwareImage.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Checks a firmware file (`update.tar`) before it goes anywhere near the
//  card: is it really firmware for a Shanling Q2, and which firmware and
//  version is it?
//
//  WHAT'S INSIDE AN update.tar (checked 2026-11-21, stock V1.36 and
//  Q2 Pod 1.8.9)
//  Both are GNU tar archives whose FIRST entry is `firmware_v20.info`, a
//  few lines of text:
//
//      Shanling Q2                ← the model it's for
//      V1.36                      ← stock writes a dotted version
//      9c13…  recovery-update/xImage
//      e0ed…  recovery-update/rootfs.squashfs
//
//  Q2 Pod writes its version without dots and one digit per part:
//  "V1890" is 1.8.9 (the same style its About screen and releases use).
//  So the second line tells the two apart. Anything else is refused: a file
//  for another player, an unknown layout, or something that isn't a tar.
//
//  HOW IT FITS
//  `FirmwareInstaller` (App) calls `inspect` on every file, downloaded or
//  chosen by the user, and `sha256` to compare with GitHub's digest and to
//  check the copy on the card.
//

import CryptoKit
import Foundation

/// What a firmware file says about itself.
struct FirmwareImageInfo: Hashable, Sendable, Codable {
    /// Which firmware it is.
    let kind: FirmwareKind
    /// Its version for people, e.g. "1.36" or "1.8.9".
    let version: String
    /// Size in bytes.
    let size: Int64

    /// e.g. "Q2 Pod 1.8.9" or "Shanling (stock) V1.36".
    var displayName: String {
        switch kind {
        case .q2Pod: return "Q2 Pod \(version)"
        case .stock: return "Shanling (stock) V\(version)"
        }
    }
}

/// Why a file isn't acceptable firmware.
enum FirmwareImageError: LocalizedError, Equatable {
    case notATar
    case missingInfo
    case wrongModel(String)
    case unknownVersion(String)
    case implausibleSize(Int64)
    case checksumMismatch
    case unexpectedKind(expected: FirmwareKind, found: FirmwareKind)

    var errorDescription: String? {
        switch self {
        case .notATar:
            return "This isn't a firmware file (update.tar)."
        case .missingInfo:
            return "This file doesn't say which player it's for, so it isn't Q2 firmware Q2 Sync recognises."
        case .wrongModel(let model):
            return "This firmware is for “\(model)”, not a Shanling Q2."
        case .unknownVersion(let line):
            return "This firmware's version (“\(line)”) isn't one Q2 Sync recognises."
        case .implausibleSize(let size):
            return "This file is the wrong size for Q2 firmware (\(size.formatted(.byteCount(style: .file))))."
        case .checksumMismatch:
            return "The download was damaged (its checksum doesn't match). Try again."
        case .unexpectedKind(let expected, let found):
            return "This file is \(found.displayName) firmware, not \(expected.displayName)."
        }
    }
}

/// Reading and checking firmware files.
enum FirmwareImage {

    /// The one file name the Q2's updater looks for, at the card root.
    static let fileName = "update.tar"

    /// The info entry at the start of every Q2 firmware archive.
    static let infoEntryName = "firmware_v20.info"

    /// The model line the info entry must start with.
    static let expectedModel = "Shanling Q2"

    /// Real files are ~54–56 MB; anything far outside is refused.
    static let plausibleSizes: ClosedRange<Int64> = 10_000_000...500_000_000

    /// Checks a firmware file and reads what it is.
    ///
    /// - Parameter url: An `update.tar` on the Mac.
    /// - Returns: Its kind, version and size.
    /// - Throws: `FirmwareImageError` if it isn't Q2 firmware.
    /// - Side effects: Reads the first few kilobytes of the file.
    static func inspect(_ url: URL) throws -> FirmwareImageInfo {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard plausibleSizes.contains(size), size % 512 == 0 else { throw FirmwareImageError.implausibleSize(size) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 8192) ?? Data()
        let (kind, version) = try readInfo(fromTarHead: head)
        return FirmwareImageInfo(kind: kind, version: version, size: size)
    }

    /// Reads the info entry from the start of a tar archive.
    ///
    /// A tar file is a series of 512-byte blocks: a header (name at bytes
    /// 0–99, size in octal at 124–135, "ustar" at 257) then the contents.
    ///
    /// - Parameter head: At least the first 1 KB of the archive.
    /// - Returns: The firmware kind and version.
    /// - Throws: `FirmwareImageError`.
    static func readInfo(fromTarHead head: Data) throws -> (FirmwareKind, String) {
        let bytes = [UInt8](head.prefix(8192))
        guard bytes.count >= 1024, Array(bytes[257..<262]) == Array("ustar".utf8) else {
            throw FirmwareImageError.notATar
        }
        let name = String(decoding: bytes[0..<100].prefix { $0 != 0 }, as: UTF8.self)
        guard name == infoEntryName else { throw FirmwareImageError.missingInfo }
        let sizeText = String(decoding: bytes[124..<136].prefix { $0 != 0 && $0 != 32 }, as: UTF8.self)
        guard let size = Int(sizeText, radix: 8), size > 0, 512 + size <= bytes.count else {
            throw FirmwareImageError.missingInfo
        }
        let text = String(decoding: bytes[512..<(512 + size)], as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2 else { throw FirmwareImageError.missingInfo }
        guard lines[0] == expectedModel else { throw FirmwareImageError.wrongModel(lines[0]) }
        guard let parsed = classify(versionLine: lines[1]) else { throw FirmwareImageError.unknownVersion(lines[1]) }
        return parsed
    }

    /// Tells stock from Q2 Pod by how the version is written.
    ///
    ///   "V1.36" → stock 1.36 (dotted)
    ///   "V1890" → Q2 Pod 1.8.9 (digits only, one per part)
    ///
    /// - Parameter versionLine: The info entry's second line.
    /// - Returns: The kind and display version, or `nil` if unrecognised.
    static func classify(versionLine: String) -> (FirmwareKind, String)? {
        let line = versionLine.trimmingCharacters(in: .whitespaces)
        if line.wholeMatch(of: /[Vv]\d+\.\d+(\.\d+)*/) != nil {
            return (.stock, String(line.dropFirst()))
        }
        if line.wholeMatch(of: /[Vv]\d{3,4}/) != nil, let version = FirmwareVersion(line) {
            return (.q2Pod, version.description)
        }
        return nil
    }

    /// The SHA-256 of a file, as 64 lowercase hex digits.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - onProgress: Called with the bytes read by each chunk.
    /// - Throws: Read errors or `CancellationError`.
    static func sha256(of url: URL, onProgress: (Int) -> Void = { _ in }) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
            onProgress(chunk.count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
