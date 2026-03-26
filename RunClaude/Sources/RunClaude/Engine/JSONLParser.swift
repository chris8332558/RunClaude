import Foundation

// MARK: - JSONL Parser

/// Parses Claude Code JSONL log files and extracts token usage records.
///
/// Claude Code stores conversation logs as JSONL files under:
///   ~/.claude/projects/<project-hash>/*.jsonl
///
/// Each line is a JSON object. Lines containing token usage have a structure like:
/// ```json
/// {
///   "type": "assistant",
///   "message": {
///     "id": "msg_...",
///     "usage": {
///       "input_tokens": 1234,
///       "output_tokens": 567,
///       "cache_creation_input_tokens": 0,
///       "cache_read_input_tokens": 890
///     },
///     "model": "claude-sonnet-4-20250514"
///   },
///   "costUSD": 0.0123,
///   "timestamp": "2025-06-01T12:34:56.789Z"
/// }
/// ```
///
/// Not every line contains usage data — we silently skip lines that don't.
struct JSONLParser {

    /// Parse a single JSONL line into a TokenRecord, if it contains usage data.
    static func parseLine(_ line: String) -> TokenRecord? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let data = line.data(using: .utf8) else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return extractTokenRecord(from: json, rawLine: line)
    }

    /// Parse multiple JSONL lines (e.g., from reading a file chunk).
    static func parseLines(_ text: String) -> [TokenRecord] {
        text.components(separatedBy: .newlines).compactMap { parseLine($0) }
    }

    /// Read and parse new lines from a file starting at the given byte offset.
    /// Returns the parsed records and the new byte offset.
    static func parseNewLines(in fileURL: URL, fromOffset offset: UInt64) -> (records: [TokenRecord], newOffset: UInt64) {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return ([], offset)
        }
        defer { try? fileHandle.close() }

        // Get file size
        let fileSize: UInt64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = attrs[.size] as? UInt64 ?? 0
        } catch {
            return ([], offset)
        }

        guard fileSize > offset else {
            return ([], offset)
        }

        // Seek to our last position and read new bytes
        try? fileHandle.seek(toOffset: offset)
        let newData = fileHandle.readDataToEndOfFile()
        let newOffset = offset + UInt64(newData.count)

        guard let text = String(data: newData, encoding: .utf8) else {
            return ([], newOffset)
        }

        let records = parseLines(text)
        return (records, newOffset)
    }

    // MARK: - Private

    private static func extractTokenRecord(from json: [String: Any], rawLine: String) -> TokenRecord? {
        // Try multiple known formats for where usage data lives

        // Format 1: message.usage (most common for assistant messages)
        if let message = json["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            return buildRecord(
                from: usage,
                model: message["model"] as? String ?? json["model"] as? String ?? "unknown",
                timestamp: extractTimestamp(from: json),
                deduplicationKey: buildDeduplicationKey(from: json, message: message, rawLine: rawLine)
            )
        }

        // Format 2: Top-level usage field
        if let usage = json["usage"] as? [String: Any] {
            return buildRecord(
                from: usage,
                model: json["model"] as? String ?? "unknown",
                timestamp: extractTimestamp(from: json),
                deduplicationKey: buildDeduplicationKey(from: json, message: nil, rawLine: rawLine)
            )
        }

        // Format 3: result.usage (some API response formats)
        if let result = json["result"] as? [String: Any],
           let usage = result["usage"] as? [String: Any] {
            return buildRecord(
                from: usage,
                model: result["model"] as? String ?? json["model"] as? String ?? "unknown",
                timestamp: extractTimestamp(from: json),
                deduplicationKey: buildDeduplicationKey(from: json, message: nil, rawLine: rawLine)
            )
        }

        return nil
    }

    private static func buildRecord(
        from usage: [String: Any],
        model: String,
        timestamp: Date,
        deduplicationKey: String
    ) -> TokenRecord {
        TokenRecord(
            timestamp: timestamp,
            model: model,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            deduplicationKey: deduplicationKey
        )
    }

    private static func extractTimestamp(from json: [String: Any]) -> Date {
        // Try ISO8601 string
        if let ts = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: ts) {
                return date
            }
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: ts) {
                return date
            }
        }

        // Try Unix timestamp
        if let ts = json["timestamp"] as? TimeInterval {
            return Date(timeIntervalSince1970: ts)
        }

        // Fallback to now
        return Date()
    }

    /// Build a deduplication key from message ID, request ID, or line hash.
    private static func buildDeduplicationKey(from json: [String: Any], message: [String: Any]?, rawLine: String) -> String {
        // Prefer message.id + request_id for stable dedup
        let messageId = message?["id"] as? String ?? json["messageId"] as? String
        let requestId = json["requestId"] as? String ?? json["request_id"] as? String

        if let mid = messageId, let rid = requestId {
            return "\(mid):\(rid)"
        }
        if let mid = messageId {
            return mid
        }

        // Fallback: hash the raw line
        var hasher = Hasher()
        hasher.combine(rawLine)
        return "hash:\(hasher.finalize())"
    }
}
