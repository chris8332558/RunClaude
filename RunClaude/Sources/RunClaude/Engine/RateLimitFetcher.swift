import Foundation
import Darwin

// MARK: - Debug helper

private let debugLogPath = "/tmp/runclaude-ratelimit.log"

private func debugLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: debugLogPath) {
            if let handle = FileHandle(forWritingAtPath: debugLogPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: debugLogPath))
        }
    }
}

// MARK: - Models

/// Usage data for a single rate-limit window (5-hour session or 7-day week).
struct RateLimitWindow: Sendable {
    /// Percentage used, 0–100.
    let percentage: Int
    /// Human-readable reset time, e.g. "6pm (America/Los_Angeles)".
    let resetsAt: String
}

/// Combined rate-limit snapshot fetched from `claude /usage`.
struct RateLimitInfo: Sendable {
    let session: RateLimitWindow?   // "Current session" (5-hour window)
    let week: RateLimitWindow?      // "Current week"   (7-day window)
    let fetchedAt: Date
}

// MARK: - Fetcher

/// Spawns `claude` in a pseudo-terminal, sends the `/usage` command, and
/// parses the resulting rate-limit output.
@MainActor
final class RateLimitFetcher: ObservableObject {
    @Published private(set) var info: RateLimitInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Public API

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Task inherits @MainActor; calling nonisolated async helpers hops off-actor
        Task {
            do {
                guard let claudePath = Self.findClaude() else {
                    self.isLoading = false
                    self.errorMessage = "claude not found"
                    return
                }
                let raw  = try await Self.runClaudeUsage(claudePath: claudePath)
                let parsed = Self.parse(raw)
                self.info = parsed
                self.isLoading = false
                if parsed == nil {
                    self.errorMessage = "No usage data in output"
                }
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Error

    private enum RateLimitError: LocalizedError {
        case claudeNotFound
        case ptyFailed

        var errorDescription: String? {
            switch self {
            case .claudeNotFound: return "claude not found"
            case .ptyFailed:      return "Failed to create PTY"
            }
        }
    }

    // MARK: - Subprocess

    /// Returns the full path of the `claude` executable, checking common locations.
    nonisolated static func findClaude() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Finds a project directory where the user has already accepted the trust dialog,
    /// so spawning `claude` there won't show the "trust this folder" prompt.
    nonisolated private static func findTrustedDirectory() -> String {
        let claudeJsonPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude.json")
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: claudeJsonPath)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let projects = json["projects"] as? [String: Any]
        else { return NSHomeDirectory() }

        for (path, value) in projects {
            guard
                let proj  = value as? [String: Any],
                let accepted = proj["hasTrustDialogAccepted"] as? Bool, accepted,
                FileManager.default.fileExists(atPath: path)
            else { continue }
            return path
        }
        return NSHomeDirectory()
    }

    /// Spawns claude in a PTY, sends `/usage`, and returns the raw terminal output.
    // nonisolated private static func runClaudeUsage(claudePath: String) async throws -> String {
    //     var master: Int32 = -1
    //     var slave: Int32 = -1
    //     guard openpty(&master, &slave, nil, nil, nil) == 0 else {
    //         throw RateLimitError.ptyFailed
    //     }

    //     let process = Process()
    //     process.executableURL = URL(fileURLWithPath: claudePath)
    //     process.environment = ProcessInfo.processInfo.environment
    //     // Run from home so claude doesn't show the "trust this folder" prompt
    //     // for an unfamiliar working directory
    //     let trustedDir = Self.findTrustedDirectory()
    //     debugLog("[RateLimitFetcher] using trusted dir: \(trustedDir)")
    //     process.currentDirectoryURL = URL(fileURLWithPath: trustedDir)

    //     let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
    //     process.standardInput  = slaveHandle
    //     process.standardOutput = slaveHandle
    //     process.standardError  =
    //         FileHandle(forWritingAtPath: "/dev/null") ?? FileHandle.standardError

    //     try process.run()
    //     close(slave)  // parent no longer needs the slave end

    //     defer {
    //         close(master)
    //         if process.isRunning { process.terminate() }
    //         process.waitUntilExit()
    //     }

    //     // Set master to non-blocking so read() never hangs
    //     let flags = fcntl(master, F_GETFL)
    //     _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)

    //     // Wait for claude to start (no trust dialog since we're in a trusted dir)
    //     try await Task.sleep(nanoseconds: 3_500_000_000)

    //     // Drain and discard everything buffered so far (welcome/REPL prompt).
    //     // This ensures the read loop below only captures fresh /usage output.
    //     var drain = [UInt8](repeating: 0, count: 4096)
    //     while read(master, &drain, 4096) > 0 {}

    //     debugLog("[RateLimitFetcher] buffer drained, sending /usage")

    //     // Send the slash command
    //     _ = "/usage\n".withCString { ptr in write(master, ptr, strlen(ptr)) }
    //     try await Task.sleep(nanoseconds: 500_000_000)   // let autocomplete handle first \r
    //     _ = "\n".withCString { ptr in write(master, ptr, strlen(ptr)) }

    //     // Collect output until it settles (2.5 s quiet) or the hard limit (10 s)
    //     var outputData = Data()
    //     let hardDeadline = Date().addingTimeInterval(10.0)
    //     var lastReadDate  = Date()

    //     while Date() < hardDeadline {
    //         var buf = [UInt8](repeating: 0, count: 4096)
    //         let n = read(master, &buf, 4096)

    //         if n > 0 {
    //             outputData.append(contentsOf: buf.prefix(n))
    //             lastReadDate = Date()
    //         } else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
    //             if outputData.count > 50 && Date().timeIntervalSince(lastReadDate) > 2.5 {
    //                 break  // output has settled
    //             }
    //             try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 s poll interval
    //         } else {
    //             break  // EOF or unrecoverable error
    //         }
    //     }

    //     let raw = String(data: outputData, encoding: .utf8)
    //         ?? String(data: outputData, encoding: .isoLatin1)
    //         ?? ""

    //     debugLog("[RateLimitFetcher] raw output (\(outputData.count) bytes):\n\(raw)\n---end raw---")

    //     return raw
    // }

    nonisolated private static func runClaudeUsage(claudePath: String) async throws -> String {
        var master: Int32 = -1
        var slave: Int32 = -1
        
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw RateLimitError.ptyFailed
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.environment = ProcessInfo.processInfo.environment

        let trustedDir = Self.findTrustedDirectory()
        debugLog("[RateLimitFetcher] using trusted dir: \(trustedDir)")
        process.currentDirectoryURL = URL(fileURLWithPath: trustedDir)

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput  = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError  = slaveHandle  // <-- capture errors too

        try process.run()
        close(slave)

        defer {
            close(master)
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        // Set non-blocking
        let flags = fcntl(master, F_GETFL)
        guard flags != -1 else {
            throw RateLimitError.ptyFailed
        }
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)

        // MARK: - Helpers

        func readAvailable(into data: inout Data) {
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(master, &buf, buf.count)
                if n > 0 {
                    data.append(contentsOf: buf.prefix(n))
                } else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    break
                } else {
                    break
                }
            }
        }

        func waitForPrompt(buffer: inout Data, timeout: TimeInterval = 10) async throws {
            let deadline = Date().addingTimeInterval(timeout)

            while Date() < deadline {
                readAvailable(into: &buffer)

                if let str = String(data: buffer, encoding: .utf8),
                str.contains("\n> ") || str.hasSuffix("> ") {
                    return
                }

                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }

            // throw RateLimitError.timeout
        }

        // MARK: - 1. Wait for initial prompt

        var buffer = Data()
        try await waitForPrompt(buffer: &buffer)

        debugLog("[RateLimitFetcher] initial prompt detected")

        // MARK: - 2. Send command

        buffer.removeAll(keepingCapacity: true)

        let cmd = "/usage\r"
        _ = cmd.withCString { write(master, $0, strlen($0)) }

        // MARK: - 3. Read until next prompt

        try await waitForPrompt(buffer: &buffer)

        // MARK: - 4. Convert output

        let raw = String(data: buffer, encoding: .utf8)
            ?? String(data: buffer, encoding: .isoLatin1)
            ?? ""

        debugLog("[RateLimitFetcher] raw output (\(buffer.count) bytes):\n\(raw)\n---end raw---")

        return raw
    }

    // MARK: - Parsing

    /// Strips ANSI escape codes and extracts session/week windows from claude output.
    nonisolated private static func parse(_ raw: String) -> RateLimitInfo? {
        // Normalize line endings: PTY uses \r\n; progress spinners emit bare \r.
        // Replace \r\n first, then any remaining lone \r, so split-by-newlines works correctly.
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Strip ANSI/VT escape sequences:
        //   \e[...m       — SGR colour/style
        //   \e[?...h/l    — DEC private mode (e.g. ?2004h bracketed paste)
        //   \e]...BEL/ST  — OSC (hyperlinks, etc.)
        //   \e[>...       — private sequences
        let ansiRegex = try? NSRegularExpression(
            pattern: "\u{1B}(?:\\[[0-9;?]*[a-zA-Z]|\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|[><=][0-9;]*[a-zA-Z]?)",
            options: []
        )
        let cleaned = ansiRegex?.stringByReplacingMatches(
            in: normalized,
            range: NSRange(normalized.startIndex..., in: normalized),
            withTemplate: ""
        ) ?? normalized

        let lines = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let linesDump = lines.enumerated().map { "  [\($0)] \($1.debugDescription)" }.joined(separator: "\n")
        debugLog("[RateLimitFetcher] cleaned lines:\n\(linesDump)")

        var session: RateLimitWindow?
        var week: RateLimitWindow?
        var context: String?
        var pendingPct: Int?

        for line in lines {
            if line.contains("Current session") {
                context = "session"; pendingPct = nil
            } else if line.contains("Current week") {
                context = "week";    pendingPct = nil
            } else if let pct = extractPercentage(from: line) {
                pendingPct = pct
            } else if line.range(of: #"^Rese\w*\s"#, options: .regularExpression) != nil,
                      let pct = pendingPct, let ctx = context {
                // Strip the leading "Resets"/"Reses" word (may be garbled by PTY \r overwrites)
                // to extract the reset-time string that follows.
                let resetsAt: String
                if line.hasPrefix("Resets ") {
                    resetsAt = String(line.dropFirst("Resets ".count))
                        .trimmingCharacters(in: .whitespaces)
                } else if let spaceRange = line.range(of: #"\s+"#, options: .regularExpression) {
                    resetsAt = String(line[spaceRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    resetsAt = line
                }
                let window = RateLimitWindow(percentage: pct, resetsAt: resetsAt)
                switch ctx {
                case "session": session = window
                case "week":    week    = window
                default:        break
                }
                pendingPct = nil
            }
        }

        guard session != nil || week != nil else { return nil }
        return RateLimitInfo(session: session, week: week, fetchedAt: Date())
    }

    /// Extracts the integer from a line containing "N% used" (space between % and "used" is optional
    /// because PTY ANSI stripping can collapse it).
    nonisolated private static func extractPercentage(from line: String) -> Int? {
        guard
            let matchRange = line.range(of: #"\d+%\s*used"#, options: .regularExpression),
            let numRange   = line.range(of: #"\d+"#, options: .regularExpression,
                                        range: line.startIndex..<matchRange.upperBound)
        else { return nil }
        return Int(line[numRange])
    }
}
