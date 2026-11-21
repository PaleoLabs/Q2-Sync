//
//  ZipExtractor.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Takes ONE file (`update.tar`) out of a zip archive, such as Shanling's
//  "Q2 Firmware V1.36.zip". Nothing else in the zip is unpacked, and the
//  file is written only where the caller says (a temp folder on the Mac).
//
//  HOW A ZIP IS LAID OUT (just what we need)
//  • At the very end: the "end of central directory" record (signature
//    PK\5\6), saying where the central directory starts and how many
//    entries it has.
//  • The central directory: one record per file (PK\1\2) with its name,
//    compression method, CRC-32, sizes and where its data starts.
//  • Each file's data follows a short local header (PK\3\4).
//  Supported: "stored" (method 0) and "deflate" (method 8), which is what
//  every zip tool writes. ZIP64 (files over 4 GB) and encryption aren't.
//
//  CHECKS
//  The extracted bytes must match the size and CRC-32 the zip records, so
//  a truncated or damaged download is caught here.
//

import Compression
import Foundation

/// Problems reading a zip.
enum ZipError: LocalizedError, Equatable {
    case notAZip
    case entryNotFound(String)
    case severalEntries(String)
    case unsupported(String)
    case damaged

    var errorDescription: String? {
        switch self {
        case .notAZip: return "This isn't a zip file Q2 Sync can read."
        case .entryNotFound(let name): return "The zip doesn't contain \(name)."
        case .severalEntries(let name): return "The zip contains more than one \(name), so Q2 Sync can't tell which to use."
        case .unsupported(let what): return "The zip uses a feature Q2 Sync can't read (\(what))."
        case .damaged: return "The zip is damaged or incomplete. Download it again."
        }
    }
}

/// Reads one file out of a zip.
enum ZipExtractor {

    /// One file listed in the zip's central directory.
    struct Entry: Equatable, Sendable {
        let path: String
        let method: UInt16
        let flags: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    /// Lists the files in a zip.
    ///
    /// - Parameter url: The zip file.
    /// - Returns: Its entries (folders included, as names ending in "/").
    /// - Throws: `ZipError` or read errors.
    static func entries(of url: URL) throws -> [Entry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()

        // The end record is 22 bytes plus a comment of up to 64 KB.
        let tailLength = min(fileSize, 22 + 65_535)
        try handle.seek(toOffset: fileSize - tailLength)
        let tail = [UInt8](try handle.read(upToCount: Int(tailLength)) ?? Data())
        guard tail.count >= 22,
              let endIndex = (0...(tail.count - 22)).reversed().first(where: { tail.u32($0) == 0x0605_4b50 }) else {
            throw ZipError.notAZip
        }
        let count = Int(tail.u16(endIndex + 10))
        let directorySize = UInt64(tail.u32(endIndex + 12))
        let directoryOffset = UInt64(tail.u32(endIndex + 16))
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw ZipError.unsupported("ZIP64") }
        guard directoryOffset + directorySize <= fileSize else { throw ZipError.damaged }

        try handle.seek(toOffset: directoryOffset)
        let directory = [UInt8](try handle.read(upToCount: Int(directorySize)) ?? Data())
        var entries: [Entry] = []
        var index = 0
        for _ in 0..<count {
            guard index + 46 <= directory.count, directory.u32(index) == 0x0201_4b50 else { throw ZipError.damaged }
            let nameLength = Int(directory.u16(index + 28))
            let extraLength = Int(directory.u16(index + 30))
            let commentLength = Int(directory.u16(index + 32))
            guard index + 46 + nameLength <= directory.count else { throw ZipError.damaged }
            let name = String(decoding: directory[(index + 46)..<(index + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(path: name,
                                 method: directory.u16(index + 10),
                                 flags: directory.u16(index + 8),
                                 crc32: directory.u32(index + 16),
                                 compressedSize: UInt64(directory.u32(index + 20)),
                                 uncompressedSize: UInt64(directory.u32(index + 24)),
                                 localHeaderOffset: UInt64(directory.u32(index + 42))))
            index += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Extracts the single file with a given name (in any folder of the zip).
    ///
    /// macOS's `__MACOSX/` and `._` metadata entries are ignored.
    ///
    /// - Parameters:
    ///   - fileName: e.g. "update.tar".
    ///   - zip: The zip file.
    ///   - destination: Where to write it (must not exist yet).
    ///   - onProgress: Called with uncompressed bytes written per chunk.
    /// - Throws: `ZipError`, `CancellationError` or file errors. A partial
    ///   output file is removed on failure.
    static func extract(fileNamed fileName: String, from zip: URL, to destination: URL,
                        onProgress: (Int) -> Void = { _ in }) throws {
        let matches = try entries(of: zip).filter { entry in
            let parts = entry.path.split(separator: "/")
            guard let last = parts.last, !entry.path.hasSuffix("/") else { return false }
            return last.lowercased() == fileName.lowercased()
                && !parts.contains("__MACOSX") && !parts.contains("..") && !last.hasPrefix("._")
        }
        guard let entry = matches.first else { throw ZipError.entryNotFound(fileName) }
        guard matches.count == 1 else { throw ZipError.severalEntries(fileName) }
        guard entry.flags & 0x1 == 0 else { throw ZipError.unsupported("encryption") }
        guard entry.method == 0 || entry.method == 8 else { throw ZipError.unsupported("compression method \(entry.method)") }
        if entry.compressedSize == 0xFFFF_FFFF || entry.uncompressedSize == 0xFFFF_FFFF {
            throw ZipError.unsupported("ZIP64")
        }

        let input = try FileHandle(forReadingFrom: zip)
        defer { try? input.close() }
        try input.seek(toOffset: entry.localHeaderOffset)
        let local = [UInt8](try input.read(upToCount: 30) ?? Data())
        guard local.count == 30, local.u32(0) == 0x0403_4b50 else { throw ZipError.damaged }
        try input.seek(toOffset: entry.localHeaderOffset + 30 + UInt64(local.u16(26)) + UInt64(local.u16(28)))

        // A plain (not atomic) create, refusing to replace an existing file.
        try Data().write(to: destination, options: .withoutOverwriting)
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            var crc = CRC32()
            var written: UInt64 = 0
            func write(_ data: Data) throws {
                try output.write(contentsOf: data)
                crc.update(data)
                written += UInt64(data.count)
                onProgress(data.count)
            }

            // `OutputFilter` with `.zlib` inflates raw DEFLATE data, which
            // is exactly what zip's method 8 stores. It hands back inflated
            // pieces, which are collected and written after each chunk.
            var inflated: [Data] = []
            let filter = entry.method == 8
                ? try OutputFilter(.decompress, using: .zlib) { data in
                    // Copy: the filter may reuse the memory behind `data`.
                    if let data { inflated.append(data.withUnsafeBytes { Data($0) }) }
                }
                : nil
            func flushInflated() throws {
                for piece in inflated { try write(piece) }
                inflated.removeAll(keepingCapacity: true)
            }
            var remaining = entry.compressedSize
            while remaining > 0 {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: Int(min(remaining, 1 << 20))), !chunk.isEmpty else {
                    throw ZipError.damaged
                }
                remaining -= UInt64(chunk.count)
                if let filter { try filter.write(chunk); try flushInflated() } else { try write(chunk) }
            }
            try filter?.finalize()
            try flushInflated()
            try output.synchronize()
            guard written == entry.uncompressedSize, crc.value == entry.crc32 else { throw ZipError.damaged }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

/// The CRC-32 checksum zip uses (the same as zlib's), computed in pieces.
struct CRC32 {

    /// The finished checksum so far.
    var value: UInt32 { ~state }

    private var state: UInt32 = 0xFFFF_FFFF

    /// Lookup table for the reversed polynomial 0xEDB88320.
    private static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// Adds bytes to the checksum.
    mutating func update(_ data: Data) {
        var crc = state
        Self.table.withUnsafeBufferPointer { table in
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                for byte in bytes {
                    crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
            }
        }
        state = crc
    }
}

private extension Array where Element == UInt8 {
    /// Little-endian 16-bit number at an offset.
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    /// Little-endian 32-bit number at an offset.
    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
