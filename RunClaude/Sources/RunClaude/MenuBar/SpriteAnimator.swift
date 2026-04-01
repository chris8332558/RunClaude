import AppKit

// MARK: - Sprite Animator

/// Cycles through sprite frames at a variable rate.
///
/// Manages clip libraries for the run and idle categories and randomly selects
/// a clip from the appropriate library whenever a cycle completes.
/// Supports hot-swapping sprite packs at runtime.
final class SpriteAnimator {

    /// Callback with the current frame image to display.
    var onFrame: ((NSImage) -> Void)?

    /// All run clips from the current pack.
    private var runClips: [AnimationClip]

    /// All idle clips from the current pack.
    private var idleClips: [AnimationClip]

    /// The clip that is currently playing.
    private var currentClip: AnimationClip

    /// Current frame index within the active clip.
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
        let all = p.clips()
        self.runClips  = all.filter { $0.category == .run }
        self.idleClips = all.filter { $0.category == .idle }
        self.currentPackId = p.id
        self.currentClip = idleClips.randomElement() ?? runClips[0]
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

        // Switch clip library if mode changed; pick a fresh random clip.
        if idle != isIdle {
            isIdle = idle
            currentFrameIndex = 0
            let candidates = idle ? idleClips : runClips
            if let clip = candidates.randomElement() {
                currentClip = clip
            }
        }
    }

    /// Switch to a different sprite pack at runtime.
    func switchPack(_ pack: SpritePack) {
        guard pack.id != currentPackId else { return }
        currentPackId = pack.id
        let all = pack.clips()
        runClips  = all.filter { $0.category == .run }
        idleClips = all.filter { $0.category == .idle }
        currentFrameIndex = 0
        let candidates = isIdle ? idleClips : runClips
        if let clip = candidates.randomElement() {
            currentClip = clip
        }
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
        let frames = currentClip.frames
        guard !frames.isEmpty else { return }

        currentFrameIndex = (currentFrameIndex + 1) % frames.count
        onFrame?(frames[currentFrameIndex])

        // At the end of each cycle, randomly select the next clip to play.
        if currentFrameIndex == 0 {
            let candidates = isIdle ? idleClips : runClips
            if let next = candidates.randomElement() {
                currentClip = next
            }
        }

        scheduleNextFrame()
    }
}
