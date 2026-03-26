import Foundation

// MARK: - Log File Watcher

/// Watches Claude Code's JSONL log directory for new files and appended data.
///
/// Uses GCD's DispatchSource file system monitoring to detect changes
/// with near-zero CPU overhead when idle.
final class LogFileWatcher {

    /// Callback fired when new token records are detected.
    var onNewRecords: (([TokenRecord]) -> Void)?

    /// The root directories to scan for JSONL files.
    private let watchPaths: [String]

    /// Tracks read offsets per file to only parse new data.
    private var fileOffsets: [String: UInt64] = [:]

    /// Set of known deduplication keys to avoid double-counting.
    private var seenKeys: Set<String> = []

    /// Dispatch sources for directory monitoring.
    private var dirSources: [DispatchSourceFileSystemObject] = []

    /// Timer for periodic full scans (catches missed events).
    private var scanTimer: DispatchSourceTimer?

    /// Queue for file I/O operations.
    private let ioQueue = DispatchQueue(label: "com.runclaude.filewatcher", qos: .utility)

    /// Scan interval in seconds.
    private let scanInterval: TimeInterval

    // MARK: - Init

    init(scanInterval: TimeInterval = 2.0) {
        self.scanInterval = scanInterval
        self.watchPaths = Self.discoverClaudeDataPaths()
    }

    deinit {
        stop()
    }

    // MARK: - Public

    func start() {
        // Initial scan
        ioQueue.async { [weak self] in
            self?.performFullScan()
        }

        // Set up directory watchers
        for path in watchPaths {
            watchDirectory(at: path)
        }

        // Periodic fallback scan (catches new subdirectories, moved files, etc.)
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + scanInterval, repeating: scanInterval)
        timer.setEventHandler { [weak self] in
            self?.performFullScan()
        }
        timer.resume()
        self.scanTimer = timer
    }

    func stop() {
        scanTimer?.cancel()
        scanTimer = nil
        for source in dirSources {
            source.cancel()
        }
        dirSources.removeAll()
    }

    // MARK: - Directory Discovery

    /// Find Claude Code data directories on this machine.
    static func discoverClaudeDataPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: [String] = []

        // Primary: ~/.claude/projects/
        let primary = "\(home)/.claude/projects"
        if FileManager.default.fileExists(atPath: primary) {
            paths.append(primary)
        }

        // Alternative: ~/.config/claude/projects/
        let alt = "\(home)/.config/claude/projects"
        if FileManager.default.fileExists(atPath: alt) {
            paths.append(alt)
        }

        return paths
    }

    // MARK: - File Scanning

    /// Scan all watched paths for JSONL files and parse new content.
    private func performFullScan() {
        let fm = FileManager.default
        var allNewRecords: [TokenRecord] = []

        for rootPath in watchPaths {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: rootPath),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }

                let path = url.path
                let currentOffset = fileOffsets[path] ?? 0
                let (records, newOffset) = JSONLParser.parseNewLines(in: url, fromOffset: currentOffset)
                fileOffsets[path] = newOffset

                // Deduplicate
                let newRecords = records.filter { record in
                    guard !seenKeys.contains(record.deduplicationKey) else { return false }
                    seenKeys.insert(record.deduplicationKey)
                    return true
                }

                allNewRecords.append(contentsOf: newRecords)
            }
        }

        if !allNewRecords.isEmpty {
            // Sort by timestamp
            let sorted = allNewRecords.sorted { $0.timestamp < $1.timestamp }
            DispatchQueue.main.async { [weak self] in
                self?.onNewRecords?(sorted)
            }
        }
    }

    // MARK: - Directory Monitoring

    /// Watch a directory for file system changes using GCD.
    private func watchDirectory(at path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .link],
            queue: ioQueue
        )

        source.setEventHandler { [weak self] in
            self?.performFullScan()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        dirSources.append(source)

        // Also watch subdirectories (one level deep for project hashes)
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: path) {
            for item in contents {
                let subpath = "\(path)/\(item)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: subpath, isDirectory: &isDir), isDir.boolValue {
                    let subFd = open(subpath, O_EVTONLY)
                    guard subFd >= 0 else { continue }

                    let subSource = DispatchSource.makeFileSystemObjectSource(
                        fileDescriptor: subFd,
                        eventMask: [.write, .extend],
                        queue: ioQueue
                    )
                    subSource.setEventHandler { [weak self] in
                        self?.performFullScan()
                    }
                    subSource.setCancelHandler {
                        close(subFd)
                    }
                    subSource.resume()
                    dirSources.append(subSource)
                }
            }
        }
    }
}
