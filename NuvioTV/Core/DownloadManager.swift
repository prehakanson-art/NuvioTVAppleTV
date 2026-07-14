import Foundation

/// A movie/episode saved to disk for offline playback.
struct DownloadedItem: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case downloading, paused, completed, failed }

    let id: String            // stable key: metaID(:season:episode)
    let metaID: String
    let type: String
    let name: String
    var poster: String?
    var background: String?
    var logo: String?
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
    var sourceURL: String
    var fileName: String       // on-disk filename inside the downloads dir
    var bytesDownloaded: Int64 = 0
    var totalBytes: Int64 = 0
    var status: Status = .downloading
    var addedAt: Date = Date()

    var fraction: Double { totalBytes > 0 ? min(Double(bytesDownloaded) / Double(totalBytes), 1) : 0 }
    var isPlayable: Bool { status == .completed }
    var sizeLabel: String? {
        let value = status == .completed ? bytesDownloaded : totalBytes
        return value > 0 ? ByteCountFormatter.string(fromByteCount: value, countStyle: .file) : nil
    }
}

/// Downloads a resolved (direct http) stream to disk so it plays with no
/// network. Progressive files only (MP4/MKV/…) — HLS playlists aren't a single
/// file and need AVAssetDownloadTask, which isn't supported here.
///
/// tvOS caveat: on-device app storage is limited and the OS may purge it under
/// storage pressure, so treat this as "offline for a while", not permanent.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [DownloadedItem] = []

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.timeoutIntervalForResource = 6 * 3600   // large files, long grace
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    /// taskIdentifier → item id, and item id → resume data for pause/resume.
    private var taskToID: [Int: String] = [:]
    private var resumeData: [String: Data] = [:]
    private var lastPublish: [String: Date] = [:]

    private let dir: URL
    private let manifest: URL

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("NuvioDownloads", isDirectory: true)
        manifest = dir.appendingPathComponent("manifest.json")
        super.init()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var d = dir
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? d.setResourceValues(values)
        loadManifest()
        // Any item left "downloading" from a previous run is stale (the session
        // didn't survive) — mark paused so the user can resume.
        for i in items.indices where items[i].status == .downloading {
            items[i].status = .paused
        }
    }

    static func key(metaID: String, season: Int?, episode: Int?) -> String {
        if let season, let episode { return "\(metaID):\(season):\(episode)" }
        return metaID
    }

    // MARK: Queries

    func item(metaID: String, season: Int?, episode: Int?) -> DownloadedItem? {
        items.first { $0.id == Self.key(metaID: metaID, season: season, episode: episode) }
    }

    /// A ready-to-play local file URL for an offline title, if fully downloaded.
    func localURL(metaID: String, season: Int?, episode: Int?) -> URL? {
        guard let item = item(metaID: metaID, season: season, episode: episode),
              item.status == .completed else { return nil }
        let url = dir.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var totalBytesOnDisk: Int64 { items.filter { $0.status == .completed }.reduce(0) { $0 + $1.bytesDownloaded } }

    /// Whole-device storage, for the Downloads storage bar.
    struct StorageInfo {
        let total: Int64        // device capacity
        let available: Int64    // free (importantUsage estimate)
        let usedByDownloads: Int64
        var used: Int64 { max(0, total - available) }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
        var downloadsFraction: Double { total > 0 ? Double(usedByDownloads) / Double(total) : 0 }
    }

    func storageInfo() -> StorageInfo {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let values = try? dir.resourceValues(forKeys: keys)
        return StorageInfo(
            total: Int64(values?.volumeTotalCapacity ?? 0),
            available: Int64(values?.volumeAvailableCapacity ?? 0),
            usedByDownloads: totalBytesOnDisk
        )
    }

    // MARK: Actions

    /// Start (or restart) a download of a resolved direct stream.
    func start(meta: MetaItem, video: MetaVideo?, stream: Stream, addonName: String) {
        guard let urlString = stream.url, let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else { return }
        let id = Self.key(metaID: meta.id, season: video?.season, episode: video?.episode)
        if let existing = item(metaID: meta.id, season: video?.season, episode: video?.episode),
           existing.status == .downloading || existing.status == .completed { return }

        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let item = DownloadedItem(
            id: id, metaID: meta.id, type: meta.type, name: meta.name,
            poster: meta.poster, background: meta.background, logo: meta.logo,
            season: video?.season, episode: video?.episode, episodeTitle: video?.title,
            sourceURL: urlString, fileName: "\(id.hashValue.magnitude).\(ext)"
        )
        upsert(item)

        let task = session.downloadTask(with: url)
        task.taskDescription = id
        taskToID[task.taskIdentifier] = id
        task.resume()
    }

    func pause(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status == .downloading else { return }
        // Cancel producing resume data; the completion delegate stores it.
        for (taskID, itemID) in taskToID where itemID == id {
            session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == taskID }
                    .flatMap { $0 as? URLSessionDownloadTask }?
                    .cancel(byProducingResumeData: { _ in })
            }
        }
        items[i].status = .paused
        saveManifest()
    }

    func resume(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let task: URLSessionDownloadTask
        if let data = resumeData[id] {
            task = session.downloadTask(withResumeData: data)
            resumeData[id] = nil
        } else if let url = URL(string: items[i].sourceURL) {
            task = session.downloadTask(with: url)
        } else { return }
        task.taskDescription = id
        taskToID[task.taskIdentifier] = id
        items[i].status = .downloading
        task.resume()
        saveManifest()
    }

    func delete(_ id: String) {
        if let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.fileName))
        }
        for (taskID, itemID) in taskToID where itemID == id {
            session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == taskID }?.cancel()
            }
        }
        resumeData[id] = nil
        items.removeAll { $0.id == id }
        saveManifest()
    }

    // MARK: Persistence

    private func upsert(_ item: DownloadedItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        else { items.insert(item, at: 0) }
        saveManifest()
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifest),
              let decoded = try? JSONDecoder().decode([DownloadedItem].self, from: data) else { return }
        items = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifest, options: .atomic)
    }

    fileprivate func finalizeDownload(id: String, tempURL: URL) {
        guard let i = items.firstIndex(where: { $0.id == id }) else {
            try? FileManager.default.removeItem(at: tempURL); return
        }
        let dest = dir.appendingPathComponent(items[i].fileName)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            items[i].status = .completed
            if items[i].totalBytes == 0 {
                items[i].bytesDownloaded = Int64((try? dest.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                items[i].totalBytes = items[i].bytesDownloaded
            } else {
                items[i].bytesDownloaded = items[i].totalBytes
            }
        } catch {
            items[i].status = .failed
        }
        saveManifest()
    }

    fileprivate func updateProgress(id: String, written: Int64, expected: Int64) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].bytesDownloaded = written
        if expected > 0 { items[i].totalBytes = expected }
        // Throttle disk writes; @Published still refreshes the UI each set.
        let now = Date()
        if now.timeIntervalSince(lastPublish[id] ?? .distantPast) > 2 {
            lastPublish[id] = now
            saveManifest()
        }
    }

    fileprivate func handleCompletion(id: String, error: Error?, resume: Data?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if let resume { resumeData[id] = resume }
        if error != nil, items[i].status != .completed {
            items[i].status = resume != nil ? .paused : (items[i].status == .paused ? .paused : .failed)
            saveManifest()
        }
    }
}

// MARK: - URLSessionDownloadDelegate (called off-main → hop to MainActor)

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // Move synchronously here — the temp file is deleted when this returns.
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.moveItem(at: location, to: staging)
        Task { @MainActor in self.finalizeDownload(id: id, tempURL: staging) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            self.updateProgress(id: id, written: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        let resume = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in self.handleCompletion(id: id, error: error, resume: resume) }
    }
}
