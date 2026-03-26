#!/usr/bin/env swift

// generate-test-data.swift
//
// Creates sample JSONL files that simulate Claude Code token usage,
// so you can test RunClaude without running an actual Claude Code session.
//
// Usage:
//   swift Scripts/generate-test-data.swift           # one-shot: write sample data
//   swift Scripts/generate-test-data.swift --live     # live mode: append data every 2s

import Foundation

let testDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/projects/_runclaude_test")

let jsonlFile = testDir.appendingPathComponent("test-session.jsonl")
let isLive = CommandLine.arguments.contains("--live")

// Ensure directory exists
try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

let models = [
    "claude-sonnet-4-20250514",
    "claude-opus-4-20250514",
    "claude-haiku-3-5-20241022"
]

let modelWeights = [0.6, 0.25, 0.15] // Sonnet most common

func randomModel() -> String {
    let r = Double.random(in: 0...1)
    var cumulative = 0.0
    for (i, w) in modelWeights.enumerated() {
        cumulative += w
        if r <= cumulative { return models[i] }
    }
    return models[0]
}

func generateRecord(at date: Date) -> String {
    let model = randomModel()
    let inputTokens = Int.random(in: 500...5000)
    let outputTokens = Int.random(in: 100...2000)
    let cacheCreate = Bool.random() ? Int.random(in: 0...1000) : 0
    let cacheRead = Bool.random() ? Int.random(in: 0...3000) : 0
    let messageId = "msg_\(UUID().uuidString.prefix(12))"
    let requestId = "req_\(UUID().uuidString.prefix(12))"

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let ts = formatter.string(from: date)

    return """
    {"type":"assistant","message":{"id":"\(messageId)","type":"message","role":"assistant","content":[{"type":"text","text":"..."}],"model":"\(model)","usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"cache_creation_input_tokens":\(cacheCreate),"cache_read_input_tokens":\(cacheRead)}},"requestId":"\(requestId)","timestamp":"\(ts)"}
    """
}

if isLive {
    // Live mode: simulate an active session by appending records every 2 seconds
    print("Live mode: appending to \(jsonlFile.path) every 2 seconds")
    print("Press Ctrl+C to stop")

    // Clear previous data
    try "".write(to: jsonlFile, atomically: true, encoding: .utf8)

    let handle = try FileHandle(forWritingTo: jsonlFile)
    handle.seekToEndOfFile()

    var burstCountdown = 0
    while true {
        let now = Date()

        // Simulate bursts of activity
        if burstCountdown > 0 {
            // During a burst: rapid token usage
            let record = generateRecord(at: now)
            handle.write((record + "\n").data(using: .utf8)!)
            burstCountdown -= 1
            Thread.sleep(forTimeInterval: Double.random(in: 0.5...2.0))
        } else if Int.random(in: 0...5) == 0 {
            // Start a new burst (20% chance each cycle)
            burstCountdown = Int.random(in: 5...20)
            print("  Burst started (\(burstCountdown) records)")
        } else {
            // Idle period
            Thread.sleep(forTimeInterval: Double.random(in: 2.0...5.0))
        }
    }
} else {
    // One-shot mode: generate a day's worth of sample data
    print("Generating sample data at \(jsonlFile.path)")

    var records: [String] = []
    let calendar = Calendar.current
    let now = Date()
    let todayStart = calendar.startOfDay(for: now)

    // Generate records throughout the day with realistic patterns
    var currentTime = todayStart.addingTimeInterval(8 * 3600) // Start at 8 AM
    let endTime = min(now, todayStart.addingTimeInterval(18 * 3600)) // End at now or 6 PM

    while currentTime < endTime {
        // Generate a "session" of 5-30 records
        let sessionLength = Int.random(in: 5...30)
        for i in 0..<sessionLength {
            let recordTime = currentTime.addingTimeInterval(Double(i) * Double.random(in: 1...5))
            guard recordTime < endTime else { break }
            records.append(generateRecord(at: recordTime))
        }

        // Gap between sessions (5-30 minutes)
        let gap = Double.random(in: 300...1800)
        currentTime = currentTime.addingTimeInterval(Double(sessionLength) * 3.0 + gap)
    }

    let content = records.joined(separator: "\n") + "\n"
    try content.write(to: jsonlFile, atomically: true, encoding: .utf8)

    print("Generated \(records.count) records")
    print("")
    print("To test live updates, run:")
    print("  swift Scripts/generate-test-data.swift --live")
}
