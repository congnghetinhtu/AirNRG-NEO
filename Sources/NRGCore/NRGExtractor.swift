import Foundation

public enum NRGError: Error, LocalizedError {
    case notNER5(String)
    case noCueChunk
    case io(String)
    case noTracks

    public var errorDescription: String? {
        switch self {
        case .notNER5(let s): return "Not a NER5 NRG image (\(s)). Only Nero DAO Audio-CD NRG is supported."
        case .noCueChunk: return "CUEX/CUES chunk not found — not an Audio-CD DAO image?"
        case .io(let s): return "I/O error: \(s)"
        case .noTracks: return "No audio tracks found in image."
        }
    }
}

public struct NRGTrack {
    public let trackNumber: Int
    public let startLBA: Int32
    public let endLBA: Int32
    public let fileName: String
    public var sectorCount: Int32 { endLBA - startLBA }
}

public struct NRGImage {
    public let tracks: [NRGTrack]
    public let dataSize: UInt64
    public let leadOutLBA: Int32?
}

private func bcdToInt(_ b: UInt8) -> Int {
    if b == 0xAA { return 0xAA }
    return Int((b >> 4) * 10 + (b & 0xF))
}

private func beUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    let b0 = UInt32(data[offset])
    let b1 = UInt32(data[offset + 1])
    let b2 = UInt32(data[offset + 2])
    let b3 = UInt32(data[offset + 3])
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

private func beInt32(_ data: Data, _ offset: Int) -> Int32 {
    return Int32(bitPattern: beUInt32(data, offset))
}

public func parseNRG(at url: URL) throws -> NRGImage {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: url.path),
          let sizeNum = attrs[.size] as? NSNumber else {
        throw NRGError.io("cannot stat file")
    }
    let fileSize = sizeNum.uint64Value
    guard fileSize > 12 else { throw NRGError.notNER5("too small") }

    let fh = try FileHandle(forReadingFrom: url)
    defer { try? fh.close() }

    try fh.seek(toOffset: fileSize - 12)
    guard let footer = try fh.read(upToCount: 12), footer.count == 12 else {
        throw NRGError.io("cannot read footer")
    }
    guard footer[footer.startIndex] == 0x4E, // N
          footer[footer.startIndex + 1] == 0x45, // E
          footer[footer.startIndex + 2] == 0x52, // R
          footer[footer.startIndex + 3] == 0x35  // 5
    else {
        throw NRGError.notNER5("missing NER5 magic")
    }
    let chunkOff = UInt64(beUInt32(footer, 8))
    let end = fileSize - 12

    var cuexData: Data? = nil
    var afnmData: Data? = nil

    var pos = chunkOff
    while pos + 8 <= end {
        try fh.seek(toOffset: pos)
        guard let hdr = try fh.read(upToCount: 8), hdr.count == 8 else { break }
        let idStr = String(bytes: hdr[0..<4], encoding: .ascii) ?? "????"
        let sz = beUInt32(hdr, 4)
        guard pos + 8 + UInt64(sz) <= end + 32 else { break }
        var payload = Data()
        if sz > 0 {
            try fh.seek(toOffset: pos + 8)
            // read in loop for large chunks (DAOX can be big, but still small)
            var remaining = Int(sz)
            while remaining > 0 {
                let n = min(remaining, 1_048_576)
                guard let part = try fh.read(upToCount: n), !part.isEmpty else { break }
                payload.append(part)
                remaining -= part.count
            }
        }
        if idStr == "CUEX" || idStr == "CUES" {
            cuexData = payload
        } else if idStr == "AFNM" {
            afnmData = payload
        }
        pos += 8 + UInt64(sz)
        if pos >= end { break }
    }

    guard let cuex = cuexData else { throw NRGError.noCueChunk }

    // CUEX: N x 8 bytes: [u8, trackBCD, index, u8, be32 LBA]
    var entries: [(track: Int, index: Int, lba: Int32)] = []
    var i = 0
    while i + 8 <= cuex.count {
        let trackBCD = cuex[cuex.startIndex + i + 1]
        let index = Int(cuex[cuex.startIndex + i + 2])
        let lba = beInt32(cuex, i + 4)
        entries.append((bcdToInt(trackBCD), index, lba))
        i += 8
    }

    var names: [String] = []
    if let afnm = afnmData {
        let parts = afnm.split(separator: 0)
        for p in parts {
            if let s = String(bytes: p, encoding: .utf8), !s.isEmpty {
                names.append(s)
            } else if let s = String(bytes: p, encoding: .isoLatin1), !s.isEmpty {
                names.append(s)
            }
        }
    }

    let idx1 = entries.filter { $0.index == 1 }.sorted { $0.lba < $1.lba }
    guard !idx1.isEmpty else { throw NRGError.noTracks }
    let leadOut = idx1.first(where: { $0.track == 0xAA })?.lba

    var tracks: [NRGTrack] = []
    for (k, e) in idx1.enumerated() {
        if e.track == 0xAA { continue }
        guard k + 1 < idx1.count else { break }
        let endLBA = idx1[k + 1].lba
        let baseName: String
        let order = tracks.count
        if order < names.count {
            baseName = names[order]
        } else {
            baseName = String(format: "Track%02d.wav", e.track)
        }
        var fname = baseName
        if !fname.lowercased().hasSuffix(".wav") { fname += ".wav" }
        fname = fname.replacingOccurrences(of: "/", with: "_")
        tracks.append(NRGTrack(trackNumber: e.track, startLBA: e.lba, endLBA: endLBA, fileName: fname))
    }
    if tracks.isEmpty { throw NRGError.noTracks }

    return NRGImage(tracks: tracks, dataSize: chunkOff, leadOutLBA: leadOut)
}

private func wavHeader(dataLen: UInt32) -> Data {
    var d = Data()
    func appendU16LE(_ v: UInt16) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
    }
    func appendU32LE(_ v: UInt32) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF))
    }
    d.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
    appendU32LE(36 + dataLen)
    d.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
    d.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt_
    appendU32LE(16)
    appendU16LE(1) // PCM
    appendU16LE(2) // stereo
    appendU32LE(44100)
    appendU32LE(44100 * 2 * 2) // byteRate
    appendU16LE(4) // blockAlign
    appendU16LE(16) // bits
    d.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
    appendU32LE(dataLen)
    return d
}

/// Extract all tracks. progress(trackIndex, trackCount, fraction, fileName)
@discardableResult
public func extractNRG(
    at url: URL,
    outputDir: URL? = nil,
    progress: ((Int, Int, Double, String) -> Void)? = nil
) throws -> [URL] {
    let image = try parseNRG(at: url)
    let fm = FileManager.default
    let outDir: URL
    if let outputDir {
        outDir = outputDir
    } else {
        let base = (url.deletingPathExtension().lastPathComponent)
        outDir = url.deletingLastPathComponent().appendingPathComponent(base + "_wav", isDirectory: true)
    }
    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

    let sectorSize: UInt64 = 2352
    let fin = try FileHandle(forReadingFrom: url)
    defer { try? fin.close() }

    var results: [URL] = []
    for (idx, t) in image.tracks.enumerated() {
        let nsec = UInt64(Int64(t.endLBA) - Int64(t.startLBA))
        let dataLen = nsec * sectorSize
        let fileOff = UInt64(Int64(t.startLBA) + 150) * sectorSize
        let outURL = outDir.appendingPathComponent(t.fileName)
        fm.createFile(atPath: outURL.path, contents: nil)
        let fout = try FileHandle(forWritingTo: outURL)
        defer { }
        do {
            // WAV header
            let hdr = wavHeader(dataLen: UInt32(dataLen & 0xFFFF_FFFF))
            try fout.write(contentsOf: hdr)
            var remaining = dataLen
            try fin.seek(toOffset: fileOff)
            while remaining > 0 {
                let want = Int(min(remaining, 1_048_576))
                guard let chunk = try fin.read(upToCount: want), !chunk.isEmpty else {
                    try? fout.close()
                    throw NRGError.io("unexpected EOF at track \(t.fileName)")
                }
                try fout.write(contentsOf: chunk)
                remaining -= UInt64(chunk.count)
                progress?(idx, image.tracks.count, 1.0 - Double(remaining) / Double(dataLen), t.fileName)
            }
            try fout.close()
        } catch {
            try? fout.close()
            throw error
        }
        results.append(outURL)
        progress?(idx + 1, image.tracks.count, 1.0, t.fileName)
    }
    return results
}
