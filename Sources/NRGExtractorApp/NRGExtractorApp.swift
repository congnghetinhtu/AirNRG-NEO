import SwiftUI
import UniformTypeIdentifiers
import AppKit
import NRGCore

@main
struct NRGExtractorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowStyle(.automatic)
    }
}

struct Job: Identifiable {
    let id = UUID()
    let inputURL: URL
    var status: String = "Queued"
    var progress: Double = 0
    var outputs: [URL] = []
    var error: String? = nil
    var isDone: Bool = false
}

@MainActor
final class Model: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var isTargeted = false

    func addURLs(_ urls: [URL]) {
        // Expand folders recursively into .nrg files so multi-dir drops work.
        var expanded: [URL] = []
        for u in urls {
            guard u.isFileURL else { continue }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                if let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let f as URL in e {
                        if f.pathExtension.lowercased() == "nrg" { expanded.append(f) }
                    }
                }
                // Empty folder drop: record as skipped so user gets feedback
                if expanded.isEmpty {
                    jobs.append(Job(inputURL: u, status: "Skipped", error: "No .nrg found in folder", isDone: true))
                }
            } else {
                expanded.append(u)
            }
        }
        for url in expanded {
            // Only .nrg (case-insensitive), but allow any dropped file with warning
            if url.pathExtension.lowercased() != "nrg" {
                var j = Job(inputURL: url, status: "Skipped", error: "Not a .nrg file", isDone: true)
                j.progress = 0
                jobs.append(j)
                continue
            }
            // Skip duplicates already queued
            if jobs.contains(where: { $0.inputURL.standardizedFileURL == url.standardizedFileURL }) { continue }
            let j = Job(inputURL: url)
            jobs.append(j)
            extract(jobID: j.id)
        }
    }

    func extract(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].status = "Extracting…"
        let input = jobs[idx].inputURL
        Task.detached(priority: .userInitiated) {
            let didAccess = input.startAccessingSecurityScopedResource()
            defer { if didAccess { input.stopAccessingSecurityScopedResource() } }
            do {
                let info = try parseNRG(at: input)
                let names = info.tracks.map { $0.fileName }.joined(separator: ", ")
                await MainActor.run {
                    self.jobs[idx].status = "\(info.tracks.count) tracks: \(names.prefix(120))"
                }
                _ = try extractNRG(at: input, outputDir: nil) { _, _, frac, fname in
                    Task { @MainActor in
                        if let k = self.jobs.firstIndex(where: { $0.id == jobID }) {
                            // overall progress: average across tracks is approximated by last callback
                            self.jobs[k].progress = frac
                            self.jobs[k].status = fname
                        }
                    }
                }
                let base = input.deletingPathExtension().lastPathComponent
                let outDir = input.deletingLastPathComponent().appendingPathComponent(base + "_wav", isDirectory: true)
                let files = (try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)) ?? []
                await MainActor.run {
                    if let k = self.jobs.firstIndex(where: { $0.id == jobID }) {
                        self.jobs[k].outputs = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
                        self.jobs[k].status = "Done — \(files.count) WAV"
                        self.jobs[k].progress = 1
                        self.jobs[k].isDone = true
                    }
                }
            } catch {
                await MainActor.run {
                    if let k = self.jobs.firstIndex(where: { $0.id == jobID }) {
                        self.jobs[k].status = "Failed"
                        self.jobs[k].error = error.localizedDescription
                        self.jobs[k].isDone = true
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = Model()
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 12) {
            Text("AirNRG Neo")
                .font(.title2).bold()
            Text("CDs, Archived!")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Drag .nrg Audio-CD images here. Each disc is split into its WAV tracks (44.1 kHz / 16-bit / stereo).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(model.isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(model.isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                    )
                    .frame(height: 130)
                VStack {
                    Image(systemName: "opticaldiscdrive.fill")
                        .font(.largeTitle)
                    Text("Drop .nrg files here")
                        .font(.headline)
                    Button("Or choose files…") { showImporter = true }
                        .buttonStyle(.link)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $model.isTargeted) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url {
                            Task { @MainActor in model.addURLs([url]) }
                        }
                    }
                }
                return true
            }

            if model.jobs.isEmpty {
                Text("No discs yet. Output goes to <name>_wav next to each .nrg.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                List {
                    ForEach($model.jobs) { $job in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.inputURL.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                            if job.isDone, job.error == nil {
                                ProgressView(value: 1) { Text(job.status).font(.caption) }
                                HStack {
                                    Text(job.status).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Reveal in Finder") {
                                        let dir = job.inputURL.deletingLastPathComponent()
                                            .appendingPathComponent(job.inputURL.deletingPathExtension().lastPathComponent + "_wav")
                                        NSWorkspace.shared.open(dir)
                                    }.font(.caption)
                                }
                            } else if let err = job.error {
                                Text("Failed: \(err)").font(.caption).foregroundStyle(.red)
                            } else {
                                ProgressView(value: job.progress) { Text(job.status).font(.caption).lineLimit(1) }
                            }
                        }.padding(.vertical, 4)
                    }
                    .onDelete { model.jobs.remove(atOffsets: $0) }
                }
                .listStyle(.inset)
            }
            Spacer()
        }
        .padding()
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.addURLs(urls)
            }
        }
    }
}
