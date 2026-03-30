import AppKit

// MARK: - Sprite Animator

/// Cycles through sprite frames at a variable rate.
///
/// Manages two animation sets (running + idle) and smoothly transitions
/// between them based on the current token velocity.
/// Supports hot-swapping sprite packs at runtime.
final class SpriteAnimator {

    /// Callback with the current frame image to display.
    var onFrame: ((NSImage) -> Void)?

    /// Running animation frames.
    private var runFrames: [NSImage]

    /// Idle animation frames.
    private var idleFrames: [NSImage]

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
    /// 0.05 gives a ~2s ramp time — slow enough to coast through brief pauses
    /// in Claude Code's output without snapping to idle.
    private let smoothing: Double = 0.05

    /// Minimum change in interval before we bother updating the timer,
    /// to avoid unnecessary timer rescheduling on tiny fluctuations.
    private let deadband: Double = 0.005

    /// The current sprite pack ID for change detection.
    private var currentPackId: String

    // MARK: - Init

    init(pack: SpritePack? = nil) {
        let p = pack ?? SpritePackRegistry.currentPack()
        self.runFrames = p.generateRunFrames()
        self.idleFrames = p.generateIdleFrames()
        self.currentPackId = p.id
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

    /// Switch to a different sprite pack at runtime.
    func switchPack(_ pack: SpritePack) {
        guard pack.id != currentPackId else { return }
        currentPackId = pack.id
        runFrames = pack.generateRunFrames()
        idleFrames = pack.generateIdleFrames()
        currentFrameIndex = 0
    }

    /// The frame size of the current pack (for NSStatusItem sizing).
    var frameSize: NSSize {
        SpritePackRegistry.pack(for: currentPackId).frameSize
    }

    // MARK: - Animation Loop

    private func scheduleNextFrame() {
        timer?.invalidate()

        // Smoothly interpolate toward target interval (exponential easing)
        let delta = (targetInterval - currentInterval) * smoothing
        if abs(delta) > deadband {
            currentInterval += delta
        } else {
            currentInterval = targetInterval
        }

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
        scheduleNextFrame()
    }
}
