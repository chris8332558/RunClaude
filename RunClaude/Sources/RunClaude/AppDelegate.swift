import AppKit

// MARK: - App Delegate

/// The application delegate. Sets up the menu bar controller and engine.
///
/// RunClaude is a "UIElement" app (LSUIElement = true), meaning it lives
/// entirely in the menu bar with no Dock icon or main window.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?
    private let engine = TokenUsageEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Log the watched paths for debugging
        let paths = engine.watchedPaths
        if paths.isEmpty {
            print("[RunClaude] Warning: No Claude Code data directories found.")
            print("[RunClaude] Expected: ~/.claude/projects/ or ~/.config/claude/projects/")
            print("[RunClaude] The app will still run but won't show any token activity until Claude Code creates log files.")
        } else {
            for path in paths {
                print("[RunClaude] Watching: \(path)")
            }
        }

        // PREVIEW — delete when done
        // showSpritePreview()

        // Set up the menu bar
        let controller = MenuBarController(engine: engine)
        controller.setup()
        self.menuBarController = controller

        print("[RunClaude] Running. Look for the animated character in your menu bar.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // PREVIEW — delete when done
    private func showSpritePreview() {
        let pack = ClawdPack()
        let clips = pack.clips()
        var clipIndex = 0
        var frameIndex = 0

        let scale: CGFloat = 12                          // 18 pt × 12 = 216 pt window
        let frameSize = pack.frameSize
        let winSize = NSSize(width: frameSize.width * scale,
                             height: frameSize.height * scale + 30) // +30 for label

        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 400, width: winSize.width, height: winSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Sprite Preview"
        panel.isFloatingPanel = true

        let imageView = NSImageView(frame: NSRect(x: 0, y: 30, width: winSize.width, height: winSize.height - 30))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 0, y: 4, width: winSize.width, height: 22)
        label.alignment = .center
        label.font = .systemFont(ofSize: 11)

        panel.contentView?.addSubview(imageView)
        panel.contentView?.addSubview(label)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            let clip = clips[clipIndex]
            guard !clip.frames.isEmpty else { return }
            frameIndex = (frameIndex + 1) % clip.frames.count
            imageView.image = clip.frames[frameIndex]
            label.stringValue = "\(clip.id)  [\(frameIndex)/\(clip.frames.count - 1)]"

            // Advance to the next clip each time a loop completes
            if frameIndex == 0 {
                clipIndex = (clipIndex + 1) % clips.count
            }
        }
    }
}
