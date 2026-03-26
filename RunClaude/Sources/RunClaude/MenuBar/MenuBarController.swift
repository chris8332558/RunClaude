import AppKit
import SwiftUI
import Combine

// MARK: - Menu Bar Controller

/// Manages the NSStatusItem, animation, and popover lifecycle.
///
/// This is the primary UI controller. It observes the TokenUsageEngine
/// and translates token velocity into animation speed.
final class MenuBarController {

    private var statusItem: NSStatusItem?
    private let animator: SpriteAnimator
    private let speedMapper: SpeedMapper
    private let engine: TokenUsageEngine
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    // MARK: - Init

    init(engine: TokenUsageEngine) {
        self.engine = engine
        self.speedMapper = SpeedMapper()
        self.animator = SpriteAnimator(pack: SpritePackRegistry.currentPack())
    }

    // MARK: - Setup

    func setup() {
        // Create the status item
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            // Set initial frame from the current sprite pack
            let currentPack = SpritePackRegistry.currentPack()
            let idleFrames = currentPack.generateIdleFrames()
            if let firstFrame = idleFrames.first {
                button.image = firstFrame
                button.image?.size = currentPack.frameSize
            }
            button.imagePosition = .imageLeft

            // Click action
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        self.statusItem = item

        // Wire up the animator to update the status item image
        animator.onFrame = { [weak self] image in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.statusItem?.button?.image = image
                self.statusItem?.button?.image?.size = self.animator.frameSize
            }
        }

        // Observe engine state changes and update animation speed
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateAnimation(for: state)
            }
            .store(in: &cancellables)

        // Start the animation
        animator.start()

        // Start the engine
        engine.start()
    }

    // MARK: - Animation Update

    private func updateAnimation(for state: UsageState) {
        let interval = speedMapper.frameInterval(for: state.tokensPerSecond)
        let idle = speedMapper.isIdle(tokensPerSecond: state.tokensPerSecond)
        animator.update(interval: interval, idle: idle)

        // Update tooltip
        let showCost = UserDefaults.standard.object(forKey: "showCostInTooltip") as? Bool ?? true
        let tier = speedMapper.speedTier(for: state.tokensPerSecond)
        var tooltip = "RunClaude — \(tier)"
        if state.tokensPerSecond >= 1 {
            tooltip += " (\(Int(state.tokensPerSecond)) tok/s)"
        }
        if showCost {
            tooltip += " | Today: \(CostCalculator.formatCost(state.todayUsage.estimatedCost))"
        }
        statusItem?.button?.toolTip = tooltip
    }

    // MARK: - Click Handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    private func togglePopover() {
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
            removeEventMonitor()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(engine: engine)
        )

        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        self.popover = popover

        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
            self?.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        // Speed info
        let speedItem = NSMenuItem(
            title: "\(speedMapper.speedTier(for: engine.state.tokensPerSecond).capitalized)"
                + (engine.state.tokensPerSecond >= 1 ? " — \(Int(engine.state.tokensPerSecond)) tok/s" : ""),
            action: nil,
            keyEquivalent: ""
        )
        speedItem.isEnabled = false
        menu.addItem(speedItem)

        // Today's cost
        let costItem = NSMenuItem(
            title: "Today: \(CostCalculator.formatCost(engine.state.todayUsage.estimatedCost)) (\(formatTokenCount(engine.state.todayUsage.totalTokens)) tokens)",
            action: nil,
            keyEquivalent: ""
        )
        costItem.isEnabled = false
        menu.addItem(costItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit RunClaude", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)

        // Remove the menu after it closes so left-click popover works again
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    // MARK: - Settings Window

    @objc private func openSettings() {
        // If window exists and is visible, just bring it front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var settingsView = SettingsView()
        settingsView.onSpritePackChanged = { [weak self] packId in
            let pack = SpritePackRegistry.pack(for: packId)
            self?.animator.switchPack(pack)
        }
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "RunClaude Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        // Bring our accessory app to front so the window is visible
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
