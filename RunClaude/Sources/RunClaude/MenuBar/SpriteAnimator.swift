import AppKit

// MARK: - Sprite Animator

/// Cycles through sprite frames at a variable rate.
///
/// Manages two animation sets (running + idle) and smoothly transitions
/// between them based on the current token velocity.
final class SpriteAnimator {

    /// Callback with the current frame image to display.
    var onFrame: ((NSImage) -> Void)?

    /// Running animation frames.
    private let runFrames: [NSImage]

    /// Idle animation frames.
    private let idleFrames: [NSImage]

    /// Current frame index within the active animation set.
    private var currentFrameIndex: Int = 0

    /// Whether we're currently in idle mode.
    private var isIdle: Bool = true

    /// Current frame interval (seconds between frames).
    private var currentInterval: TimeInterval = 0.8

    /// Target interval (we smooth toward this to avoid jarring speed changes).
    private var targetInterval: TimeInterval = 0.8

    /// The animation timer.
    private var timer: Timer?

    /// Smoothing factor for interval transitions (0-1, lower = smoother).
    private let smoothing: Double = 0.15

    // MARK: - Init

    init(
        runFrames: [NSImage]? = nil,
        idleFrames: [NSImage]? = nil
    ) {
        self.runFrames = runFrames ?? SpriteGenerator.generateRunFrames()
        self.idleFrames = idleFrames ?? SpriteGenerator.generateIdleFrames()
    }

    // MARK: - Control

    /// Start the animation loop.
    func start() {
        scheduleNextFrame()
    }

    /// Stop the animation loop.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Update the animation speed and mode.
    /// Call this whenever the token velocity changes.
    func update(interval: TimeInterval, idle: Bool) {
        targetInterval = interval

        // Switch animation set if mode changed
        if idle != isIdle {
            isIdle = idle
            currentFrameIndex = 0
        }
    }

    // MARK: - Animation Loop

    private func scheduleNextFrame() {
        timer?.invalidate()

        // Smoothly interpolate toward target interval
        currentInterval += (targetInterval - currentInterval) * smoothing

        timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    private func advanceFrame() {
        let frames = isIdle ? idleFrames : runFrames
        guard !frames.isEmpty else { return }

        currentFrameIndex = (currentFrameIndex + 1) % frames.count
        let frame = frames[currentFrameIndex]

        onFrame?(frame)

        // Schedule the next frame
        scheduleNextFrame()
    }
}
