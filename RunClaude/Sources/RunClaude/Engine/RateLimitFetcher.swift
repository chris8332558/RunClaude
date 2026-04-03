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

/// Spawns `claude` in a pseudo-terminal once, keeps it alive, and sends
/// `/usage` on each refresh instead of restarting the process every time.
@MainActor
final class RateLimitFetcher: ObservableObject {
    @Published private(set) var info: RateLimitInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// Results are cached for this many seconds; `refresh(force:)` with `force: true` bypasses it.
    static let cacheMaxAge: TimeInterval = 5 * 60

    // Persistent PTY state.
    // nonisolated(unsafe) is required because deinit is not actor-isolated in Swift 5.9.
    // These are only mutated from within the @MainActor Task in refresh(), which is
    // serialized by the isLoading guard, so access is safe.
    nonisolated(unsafe) private var persistentMaster: Int32 = -1
    nonisolated(unsafe) private var persistentProcess: Process?

    deinit {
        if let process = persistentProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        if persistentMaster != -1 {
            close(persistentMaster)
        }
    }

    // MARK: - Public API

    /// Fetches usage data.
    /// - Parameter force: When `true` always re-fetches even if the cache is fresh.
    ///   Pass `false` (the default) for automatic/background refreshes so the
    ///   first open is fast and the expensive PTY spawn is avoided on repeat opens.
    func refresh(force: Bool = false) {
        guard !isLoading else { return }

        // Serve from cache if the data is fresh enough and the caller didn't force.
        if !force, let existing = info,
           Date().timeIntervalSince(existing.fetchedAt) < Self.cacheMaxAge {
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let claudePath = Self.findClaude() else {
                    self.isLoading = false
                    self.errorMessage = "claude not found"
                    return
                }

                // (Re)start the persistent process if it isn't running.
                if persistentProcess == nil || !persistentProcess!.isRunning {
                    if persistentMaster != -1 {
                        close(persistentMaster)
                        persistentMaster = -1
                    }
                    let (proc, master) = try await Self.startPersistentProcess(claudePath: claudePath)
                    persistentProcess = proc
                    persistentMaster = master
                }

                let raw    = try await Self.fetchUsage(master: persistentMaster)
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

    // MARK: - Process discovery

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
                let proj     = value as? [String: Any],
                let accepted = proj["hasTrustDialogAccepted"] as? Bool, accepted,
                FileManager.default.fileExists(atPath: path)
            else { continue }
            return path
        }
        return NSHomeDirectory()
    }

    // MARK: - Persistent PTY lifecycle

    /// Spawns `claude` in a PTY, waits for the initial REPL prompt, and returns
    /// the persistent (Process, master fd) pair.  The caller owns cleanup.
    nonisolated private static func startPersistentProcess(claudePath: String) async throws -> (Process, Int32) {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw RateLimitError.ptyFailed
        }

        let process = Process()
        // Spawn via login shell so the full user environment (PATH, NODE_PATH, etc.)
        // is loaded. This matters when launched from Xcode, which inherits a stripped
        // env that can prevent the claude CLI from starting properly and causes the
        // waitFor() call to hit its 10-second timeout. `exec` replaces zsh with
        // claude so Process tracking (isRunning, terminate) still targets claude.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments     = ["-l", "-c", "exec \"\(claudePath)\""]
        process.environment   = ProcessInfo.processInfo.environment

        let trustedDir = Self.findTrustedDirectory()
        debugLog("[RateLimitFetcher] using trusted dir: \(trustedDir)")
        process.currentDirectoryURL = URL(fileURLWithPath: trustedDir)

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput  = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError  = slaveHandle

        do {
            try process.run()
        } catch {
            close(master)
            close(slave)
            throw error
        }
        close(slave)

        let flags = fcntl(master, F_GETFL)
        guard flags != -1 else {
            close(master)
            process.terminate()
            throw RateLimitError.ptyFailed
        }
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)

        // Wait for the REPL prompt before returning.
        var buffer = Data()
        try await waitFor(master: master, buffer: &buffer)
        debugLog("[RateLimitFetcher] persistent process ready, prompt detected")

        return (process, master)
    }

    /// Sends `/usage` to the already-running REPL and returns the raw terminal output.
    nonisolated private static func fetchUsage(master: Int32) async throws -> String {
        // Drain any stale output so we only capture the fresh /usage response.
        var discard = Data()
        readAvailable(master: master, into: &discard)

        // Send the slash command.
        var buffer = Data()
        let cmd = "/usage\r"
        _ = cmd.withCString { write(master, $0, strlen($0)) }

        // "Esc to cancel" is the last line claude renders in the /usage panel,
        // appearing before the trailing "> " prompt. Stopping here avoids waiting
        // for the REPL to redraw its input line, which saves ~0.5–1 s.
        try await waitFor(master: master, buffer: &buffer,
                          earlyExit: { $0.contains("Esc to cancel") })

        let raw = String(data: buffer, encoding: .utf8)
            ?? String(data: buffer, encoding: .isoLatin1)
            ?? ""

        debugLog("[RateLimitFetcher] raw output (\(buffer.count) bytes):\n\(raw)\n---end raw---")

        // Dismiss the usage panel. A short pause lets the REPL process ESC and redraw
        // before the next call's drain step clears the leftover output.
        let esc = "\u{1B}"
        _ = esc.withCString { write(master, $0, strlen($0)) }
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 s

        return raw
    }

    // MARK: - PTY helpers

    nonisolated private static func readAvailable(master: Int32, into data: inout Data) {
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(master, &buf, buf.count)
            if n > 0 {
                data.append(contentsOf: buf.prefix(n))
            } else {
                break
            }
        }
    }

    /// Polls until the buffer contains a REPL prompt or `earlyExit` returns true.
    nonisolated private static func waitFor(
        master: Int32,
        buffer: inout Data,
        timeout: TimeInterval = 10,
        earlyExit: (String) -> Bool = { _ in false }
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            readAvailable(master: master, into: &buffer)

            if let str = String(data: buffer, encoding: .utf8) {
                if str.contains("\n> ") || str.hasSuffix("> ") { return }
                if earlyExit(str) { return }
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
        }
    }

    // MARK: - Parsing

    /// Strips ANSI escape codes and extracts session/week windows from claude output.
    nonisolated private static func parse(_ raw: String) -> RateLimitInfo? {
        // Normalize line endings: PTY uses \r\n; progress spinners emit bare \r.
        // Replace \r\n first, then any remaining lone \r, so split-by-newlines works correctly.
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // The Claude CLI does differential terminal redraws using cursor-forward sequences
        // (ESC[NC) as stand-ins for characters already on screen. Stripping them as plain
        // escape codes drops those characters entirely ("Current session" → "Curretsession").
        // Replace them with a space first so word boundaries are preserved.
        let cursorFwdReplaced = normalized.replacingOccurrences(
            of: "\u{1B}\\[[0-9]+C",
            with: " ",
            options: .regularExpression
        )

        // Strip remaining ANSI/VT escape sequences:
        //   \e[...m       — SGR colour/style
        //   \e[?...h/l    — DEC private mode (e.g. ?2004h bracketed paste)
        //   \e]...BEL/ST  — OSC (hyperlinks, etc.)
        //   \e[>...       — private sequences
        let ansiRegex = try? NSRegularExpression(
            pattern: "\u{1B}(?:\\[[0-9;?]*[a-zA-Z]|\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|[><=][0-9;]*[a-zA-Z]?)",
            options: []
        )
        let cleaned = ansiRegex?.stringByReplacingMatches(
            in: cursorFwdReplaced,
            range: NSRange(cursorFwdReplaced.startIndex..., in: cursorFwdReplaced),
            withTemplate: ""
        ) ?? cursorFwdReplaced

        let lines = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let linesDump = lines.enumerated().map { "  [\($0)] \($1.debugDescription)" }.joined(separator: "\n")
        debugLog("[RateLimitFetcher] cleaned lines:\n\(linesDump)")

        var session: RateLimitWindow?
        var week: RateLimitWindow?
        var context: String?
        var pendingPct: Int?

        for line in lines {
            if line.contains("session") {
                context = "session"; pendingPct = nil
            } else if line.contains("week") {
                context = "week";    pendingPct = nil
            } else if let pct = extractPercentage(from: line) {
                pendingPct = pct
            } else if line.range(of: #"^Rese\w*"#, options: .regularExpression) != nil,
                      let pct = pendingPct, let ctx = context {
                // Strip the leading "Resets"/"Reses" word (may be garbled by PTY \r overwrites,
                // merging the word with the next token e.g. "Reses2pm"). Match only the letter
                // portion so digits (the time) aren't consumed along with the garbled prefix.
                let resetsAt: String
                if let wordEnd = line.range(of: #"^Rese[a-zA-Z]*"#, options: .regularExpression) {
                    resetsAt = String(line[wordEnd.upperBound...])
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
