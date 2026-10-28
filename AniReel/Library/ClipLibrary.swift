import Foundation
import Observation

struct ClipRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
    let styleID: String
    let byteSize: Int64
}

/// The library's metadata, newest clip first. Pure value: all ordering and size rules live here.
struct ClipLibraryIndex: Codable, Equatable {
    private(set) var clips: [ClipRecord] = []

    var totalBytes: Int64 { clips.reduce(0) { $0 + $1.byteSize } }

    mutating func insert(_ clip: ClipRecord) {
        let position = clips.firstIndex { $0.createdAt < clip.createdAt } ?? clips.endIndex
        clips.insert(clip, at: position)
    }

    @discardableResult
    mutating func remove(id: UUID) -> ClipRecord? {
        guard let position = clips.firstIndex(where: { $0.id == id }) else { return nil }
        return clips.remove(at: position)
    }

    /// Drops records whose video file is gone (e.g. removed by a failed write or the system).
    func reconciled(existingFiles: Set<String>) -> ClipLibraryIndex {
        var copy = self
        copy.clips = clips.filter { existingFiles.contains($0.fileName) }
        return copy
    }
}

/// App-local copies of every clip saved to Photos (docs/PHASE6_BRIEF.md C). No size cap in V1;
/// the total is shown in Settings. Excluded from iCloud backup because Photos already has a copy.
@MainActor
@Observable
final class ClipLibrary {
    private(set) var index: ClipLibraryIndex

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let file: JSONFileStore<ClipLibraryIndex>

    init(directory: URL = AppDirectories.applicationSupport.appendingPathComponent("Clips", isDirectory: true)) {
        self.directory = directory
        file = JSONFileStore(url: directory.appendingPathComponent("library.json"))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        index = (file.load() ?? ClipLibraryIndex()).reconciled(existingFiles: Set(names))
    }

    var clips: [ClipRecord] { index.clips }

    func url(for clip: ClipRecord) -> URL {
        directory.appendingPathComponent(clip.fileName)
    }

    /// Copies the finished temp file in; the caller still owns (and deletes) the temp file.
    @discardableResult
    func importClip(from source: URL, duration: TimeInterval, styleID: StyleID, now: Date = .now) throws -> ClipRecord {
        try prepareDirectory()
        let id = UUID()
        let fileName = "\(id.uuidString).mp4"
        let destination = directory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: destination)
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let clip = ClipRecord(id: id, fileName: fileName, createdAt: now, duration: duration, styleID: styleID.rawValue, byteSize: Int64(size))
        index.insert(clip)
        try file.save(index)
        return clip
    }

    func delete(_ clip: ClipRecord) {
        try? FileManager.default.removeItem(at: url(for: clip))
        index.remove(id: clip.id)
        try? file.save(index)
    }

    func deleteAll() {
        clips.forEach { try? FileManager.default.removeItem(at: url(for: $0)) }
        index = ClipLibraryIndex()
        try? file.save(index)
    }

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }
}
