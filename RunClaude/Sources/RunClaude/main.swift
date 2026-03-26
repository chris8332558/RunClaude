import AppKit

// MARK: - Entry Point

// RunClaude: A macOS menu bar app that animates a sprite character
// at a speed proportional to your live Claude Code token usage.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Don't activate (no dock icon, no main window — pure menu bar app)
app.setActivationPolicy(.accessory)

app.run()
