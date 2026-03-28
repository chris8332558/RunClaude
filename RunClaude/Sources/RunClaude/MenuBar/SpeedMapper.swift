import Foundation

// MARK: - Speed Mapper

/// Maps token velocity (tokens/second) to animation frame interval.
///
/// Uses logarithmic scaling so that:
/// - 0 tok/s → idle animation (~1 frame/sec)
/// - 50 tok/s → slow walk
/// - 200 tok/s → jog
/// - 500 tok/s → run
/// - 1000+ tok/s → sprint (~25 fps)
struct SpeedMapper {

    /// The slowest animation interval (idle breathing/blinking).
    let idleInterval: TimeInterval

    /// The fastest animation interval (full sprint).
    let sprintInterval: TimeInterval

    /// Scaling factor for the logarithmic curve.
    /// Higher = reaches max speed at lower token rates.
    let scaleFactor: Double

    /// Threshold below which we show the idle animation.
    let idleThreshold: Double

    init(
        idleInterval: TimeInterval = 0.4,
        sprintInterval: TimeInterval = 0.03,
        scaleFactor: Double = 40.0,
        idleThreshold: Double = 1.0
    ) {
        self.idleInterval = idleInterval
        self.sprintInterval = sprintInterval
        self.scaleFactor = scaleFactor
        self.idleThreshold = idleThreshold
    }

    /// Convert tokens/second to a frame interval in seconds.
    func frameInterval(for tokensPerSecond: Double) -> TimeInterval {
        guard tokensPerSecond >= idleThreshold else {
            return idleInterval
        }

        // Logarithmic scaling: fast ramp at low rates, diminishing returns at high rates
        let speed = log2(1.0 + tokensPerSecond / scaleFactor)
        let interval = max(sprintInterval, 0.1 / speed)
        return min(interval, idleInterval)
    }

    /// Whether to use the idle animation set vs the running set.
    func isIdle(tokensPerSecond: Double) -> Bool {
        tokensPerSecond < idleThreshold
    }

    /// A human-readable description of the current speed tier.
    func speedTier(for tokensPerSecond: Double) -> String {
        switch tokensPerSecond {
        case ..<1:      return "idle"
        case ..<50:     return "walking"
        case ..<200:    return "jogging"
        case ..<500:    return "running"
        default:        return "sprinting"
        }
    }
}
