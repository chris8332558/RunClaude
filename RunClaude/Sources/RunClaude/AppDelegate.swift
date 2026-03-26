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

        // Set up the menu bar
        let controller = MenuBarController(engine: engine)
        controller.setup()
        self.menuBarController = controller

        print("[RunClaude] Running. Look for the animated character in your menu bar.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}
