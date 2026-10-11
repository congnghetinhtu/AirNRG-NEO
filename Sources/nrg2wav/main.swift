import Foundation
import NRGCore

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: nrg2wav input.nrg [output_dir]")
    exit(1)
}
let input = URL(fileURLWithPath: args[1])
let out: URL? = args.count >= 3 ? URL(fileURLWithPath: args[2], isDirectory: true) : nil
do {
    let info = try parseNRG(at: input)
    print("Tracks: \(info.tracks.count), dataSize: \(info.dataSize)")
    for t in info.tracks {
        print("  #\(t.trackNumber) LBA \(t.startLBA)->\(t.endLBA) (\(t.sectorCount) sectors) \(t.fileName)")
    }
    let urls = try extractNRG(at: input, outputDir: out) { idx, total, frac, name in
        if frac == 1.0 {
            print("[\(idx)/\(total)] \(name) done")
        }
    }
    print("Wrote \(urls.count) files to \(urls.first?.deletingLastPathComponent().path ?? "?")")
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(2)
}
