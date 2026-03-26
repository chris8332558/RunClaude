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
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    // MARK: - Init

    init(engine: TokenUsageEngine) {
        self.engine = engine
        self.speedMapper = SpeedMapper()
        self.animator = SpriteAnimator()
    }

    // MARK: - Setup

    func setup() {
        // Create the status item
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            // Set initial frame
            let idleFrames = SpriteGenerator.generateIdleFrames()
            if let firstFrame = idleFrames.first {
                button.image = firstFrame
                button.image?.size = SpriteGenerator.frameSize
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
                self?.statusItem?.button?.image = image
                self?.statusItem?.button?.image?.size = SpriteGenerator.frameSize
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

        // Update tooltip with current stats
        let tier = speedMapper.speedTier(for: state.tokensPerSecond)
        let cost = CostCalculator.formatCost(state.todayUsage.estimatedCost)
        statusItem?.button?.toolTip = "RunClaude — \(tier) (\(Int(state.tokensPerSecond)) tok/s) | Today: \(cost)"
    }

    // MARK: - Popover

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            // Right-click: show context menu
            showContextMenu()
        } else {
            // Left-click: toggle popover
            togglePopover()
        }
    }

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
        popover.contentSize = NSSize(width: 320, height: 400)
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

    private func showContextMenu() {
        let menu = NSMenu()

        // Speed info
        let speedItem = NSMenuItem(
            title: "Speed: \(speedMapper.speedTier(for: engine.state.tokensPerSecond)) (\(Int(engine.state.tokensPerSecond)) tok/s)",
            action: nil,
            keyEquivalent: ""
        )
        speedItem.isEnabled = false
        menu.addItem(speedItem)

        // Cost info
        let costItem = NSMenuItem(
            title: "Today: \(CostCalculator.formatCost(engine.state.todayUsage.estimatedCost))",
            action: nil,
            keyEquivalent: ""
        )
        costItem.isEnabled = false
        menu.addItem(costItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit RunClaude", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)

        // Remove the menu after it closes so left-click works again
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
