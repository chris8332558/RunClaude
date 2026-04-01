import AppKit

// MARK: - Animation Clip

/// Broad category that determines when a clip is eligible to play.
enum AnimationCategory {
    case run   // plays while Claude is active / processing
    case idle  // plays while Claude is waiting
}

/// A single named, looping animation sequence within a sprite pack.
struct AnimationClip {
    /// Unique identifier within its pack (e.g. "run", "run_angled", "idle").
    let id: String
    /// Determines which state can play this clip.
    let category: AnimationCategory
    /// The frames that make up the loop.
    let frames: [NSImage]
}

// MARK: - Sprite Pack Protocol

/// A sprite pack provides one or more named animation clips.
///
/// **New-style packs** implement `clips()` and get `generateRunFrames()` /
/// `generateIdleFrames()` for free via the extension defaults.
///
/// **Legacy packs** implement `generateRunFrames()` / `generateIdleFrames()`
/// and get a single-variant `clips()` for free via the extension defaults.
protocol SpritePack {
    /// Unique identifier for this pack (used in UserDefaults).
    var id: String { get }
    /// Display name shown in Settings.
    var displayName: String { get }
    /// The size of each frame in points.
    var frameSize: NSSize { get }
    /// Multiplier applied to the frame interval from SpeedMapper (>1 = slower, <1 = faster).
    /// Default is 1.0 (no change).
    var frameIntervalScale: Double { get }
    /// All animation clips this pack provides.
    /// Default implementation wraps `generateRunFrames()` / `generateIdleFrames()`.
    func clips() -> [AnimationClip]
    /// Legacy: single run animation.  Default delegates to `clips()`.
    func generateRunFrames() -> [NSImage]
    /// Legacy: single idle animation.  Default delegates to `clips()`.
    func generateIdleFrames() -> [NSImage]
}

extension SpritePack {
    var frameIntervalScale: Double { 1.0 }

    // New-style pack: implements clips() → legacy callers work via these defaults.
    func generateRunFrames() -> [NSImage] {
        clips().first { $0.category == .run }?.frames ?? []
    }
    func generateIdleFrames() -> [NSImage] {
        clips().first { $0.category == .idle }?.frames ?? []
    }

    // Legacy pack: implements generateRun/IdleFrames() → clips() works via this default.
    func clips() -> [AnimationClip] {
        [
            AnimationClip(id: "run",  category: .run,  frames: generateRunFrames()),
            AnimationClip(id: "idle", category: .idle, frames: generateIdleFrames()),
        ]
    }

    /// Returns a random clip for the given category, or nil if none are available.
    func randomClip(for category: AnimationCategory) -> AnimationClip? {
        clips().filter { $0.category == category }.randomElement()
    }
}

// MARK: - Sprite Pack Registry

/// Central registry for all available sprite packs.
struct SpritePackRegistry {
    static let allPacks: [SpritePack] = [
        ClawdPack(),
        Clawd2Pack()
    ]

    static let defaultPackId = "clawd"

    static func pack(for id: String) -> SpritePack {
        allPacks.first { $0.id == id } ?? allPacks[0]
    }

    static func currentPack() -> SpritePack {
        let id = UserDefaults.standard.string(forKey: "selectedSpritePack") ?? defaultPackId
        return pack(for: id)
    }
}

// MARK: - Pack 1: Claude Bean (default)

/// The Claude-inspired rounded bean/capsule character.
struct ClawdPack: SpritePack {
    let id = "clawd"
    let displayName = "Clawd"
    let frameSize = NSSize(width: 18, height: 18)

    func clips() -> [AnimationClip] {
        [
            AnimationClip(id: "run",
                          category: .run,
                          frames: (0..<8).map { drawRunFrame(phase: Double($0) / 8.0) }),
            AnimationClip(id: "run_two",
                          category: .run,
                          frames: (0..<8).map { drawRunFrameTwo(phase: Double($0) / 8.0) }),
            // AnimationClip(id: "run_angled",
            //               category: .run,
            //               frames: (0..<8).map { drawAngledRunFrame(phase: Double($0) / 8.0) }),
            AnimationClip(id: "idle",
                          category: .idle,
                          frames: (0..<4).map { drawIdleFrame(phase: Double($0) / 4.0) }),
        ]
    }

    private func drawRunFrame(phase: Double) -> NSImage {
        let size = frameSize  // 18×18
        let image = NSImage(size: size, flipped: false) { _ in
            let px: CGFloat = 2.0
            let cx: CGFloat = size.width / 2
            let groundY: CGFloat = 1.5

            // Body sways left/right; slight vertical bounce on each step
            let sway   = CGFloat(sin(phase * .pi * 2)) * 0.5
            let bounce = abs(CGFloat(sin(phase * .pi * 2))) * 1.0

            NSColor.black.setFill()

            // Body — same 6×5 px proportions as idle, shifted by sway + bounce
            let bodyW = 6 * px
            let bodyH = 5 * px
            let bodyBottom = groundY + 1.5 * px + bounce
            let bodyRect = NSRect(x: cx - bodyW / 2 + sway, y: bodyBottom, width: bodyW, height: bodyH)
            NSBezierPath(rect: bodyRect).fill()

            // Arms — anchored to bodyRect so they always track both sway (X) and bounce (Y);
            // left/right pump in opposite directions for a natural running look.
            let armW = 2 * px
            let armH = 2 * px
            let armBaseY  = bodyRect.minY + (bodyH - armH) / 2
            let armSwing  = CGFloat(sin(phase * .pi * 2)) * 1.2
            NSBezierPath(rect: NSRect(x: bodyRect.minX - armW, y: armBaseY + armSwing, width: armW, height: armH)).fill()
            NSBezierPath(rect: NSRect(x: bodyRect.maxX,        y: armBaseY + armSwing, width: armW, height: armH)).fill()

            // Legs — 4 legs, alternating pairs lift off the ground
            let legW = px
            let gap  = (bodyW - legW) / 3
            for i in 0...3 {
                let xPos     = bodyRect.minX + CGFloat(i) * gap
                let legPhase = (i % 2 == 0) ? phase : phase + 0.5
                let lift     = max(0, CGFloat(sin(legPhase * .pi * 2))) * 1.0 
                NSBezierPath(rect: NSRect(x: xPos, y: groundY + lift, width: legW, height: bodyBottom - groundY - lift)).fill()
            }

            // Eyes — transparent cutouts, same position logic as idle
            NSGraphicsContext.current?.compositingOperation = .clear
            let eyeSize = px
            let eyeY    = bodyRect.minY + bodyH - 1.5 * px
            NSBezierPath(rect: NSRect(x: bodyRect.midX - 3.0 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)).fill()
            NSBezierPath(rect: NSRect(x: bodyRect.midX + 3.0 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            return true
        }
        image.isTemplate = true
        return image
    }


    private func drawRunFrameTwo(phase: Double) -> NSImage {
        let size = frameSize  // 18×18
        let image = NSImage(size: size, flipped: false) { _ in
            let px: CGFloat = 2.0
            let cx: CGFloat = size.width / 2
            let groundY: CGFloat = 1.5

            // Body sways left/right; slight vertical bounce on each step
            let sway   = CGFloat(sin(phase * .pi * 2)) * 0.5
            let bounce = abs(CGFloat(sin(phase * .pi * 2))) * 1.0

            NSColor.black.setFill()

            // Body — same 6×5 px proportions as idle, shifted by sway + bounce
            let bodyW = 6 * px
            let bodyH = 5 * px
            let bodyBottom = groundY + 1.5 * px + bounce
            let bodyRect = NSRect(x: cx - bodyW / 2 + sway, y: bodyBottom, width: bodyW, height: bodyH)
            NSBezierPath(rect: bodyRect).fill()

            // Arms — anchored to bodyRect so they always track both sway (X) and bounce (Y);
            // left/right pump in opposite directions for a natural running look.
            let armW = 2 * px
            let armH = 2 * px
            let armBaseY  = bodyRect.minY + (bodyH - armH) / 2
            let armSwing  = CGFloat(sin(phase * .pi * 2)) * 0.5 
            NSBezierPath(rect: NSRect(x: bodyRect.minX - armW, y: armBaseY - armSwing, width: armW, height: armH)).fill()
            NSBezierPath(rect: NSRect(x: bodyRect.maxX,        y: armBaseY + armSwing, width: armW, height: armH)).fill()

            // Legs — 4 legs, each staggered by ¼ cycle so they lift one at a time
            let legW = px
            let gap  = (bodyW - legW) / 3
            for i in 0...3 {
                let xPos     = bodyRect.minX + CGFloat(i) * gap
                let legPhase = phase + Double(i) * 0.25
                let lift     = max(0, CGFloat(sin(legPhase * .pi * 2))) * 1.5
                NSBezierPath(rect: NSRect(x: xPos, y: groundY + lift, width: legW, height: bodyBottom - groundY - lift)).fill()
            }

            // Eyes — transparent cutouts, same position logic as idle
            NSGraphicsContext.current?.compositingOperation = .clear
            let eyeSize = px
            let eyeY    = bodyRect.minY + bodyH - 1.5 * px
            NSBezierPath(rect: NSRect(x: bodyRect.midX - 1.0 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)).fill()
            NSBezierPath(rect: NSRect(x: bodyRect.midX + 4.0 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws the character from a 45-degree angled perspective.
    /// The body is rendered as a parallelogram (bottom edge at ground position,
    /// top edge shifted right by `shear` pts) to simulate depth foreshortening.
    private func drawAngledRunFrame(phase: Double) -> NSImage {
        let size = frameSize  // 18×18
        let image = NSImage(size: size, flipped: false) { _ in
            let px: CGFloat = 2.0
            let cx: CGFloat = size.width / 2
            let groundY: CGFloat = 1.5
            // Horizontal offset between the body's bottom and top edges.
            let shear: CGFloat = 3.0

            let bounce = abs(CGFloat(sin(phase * .pi * 2))) * 0.8

            NSColor.black.setFill()

            let bodyW: CGFloat = 5 * px   // slightly narrower to sell the foreshortening
            let bodyH: CGFloat = 5 * px
            let bodyBottom = groundY + 1.5 * px + bounce
            let bodyTopY   = bodyBottom + bodyH
            // Shift the whole body left so the sheared top stays inside the canvas.
            let bx = cx - bodyW / 2 - shear * 0.5

            // Body as parallelogram — bottom row at bx…bx+bodyW,
            // top row shifted right by `shear`.
            let body = NSBezierPath()
            body.move(to: NSPoint(x: bx,                 y: bodyBottom))
            body.line(to: NSPoint(x: bx + bodyW,         y: bodyBottom))
            body.line(to: NSPoint(x: bx + bodyW + shear, y: bodyTopY))
            body.line(to: NSPoint(x: bx + shear,         y: bodyTopY))
            body.close()
            body.fill()

            // Arms — anchored at mid-body height (shear × 0.5 offset from body edges).
            let armSwing    = CGFloat(sin(phase * .pi * 2)) * 1.0
            let armMidShear = shear * 0.5
            let armY        = bodyBottom + (bodyH - 1.5 * px) / 2

            // Near arm (right side — larger, closer to viewer)
            NSBezierPath(rect: NSRect(
                x: bx + bodyW + armMidShear,
                y: armY + armSwing,
                width: 1.5 * px, height: 1.5 * px
            )).fill()

            // Far arm (left side — smaller, receding)
            NSBezierPath(rect: NSRect(
                x: bx + armMidShear - 1.5 * px,
                y: armY - armSwing,
                width: 1.5 * px, height: px
            )).fill()

            // Legs — four legs, alternating lift, evenly spaced across body width
            let legW = px
            let gap  = (bodyW - legW) / 3
            for i in 0...3 {
                let legPhase = (i % 2 == 0) ? phase : phase + 0.5
                let lift     = max(0, CGFloat(sin(legPhase * .pi * 2))) * 1.0
                let xPos     = bx + CGFloat(i) * gap
                NSBezierPath(rect: NSRect(
                    x: xPos, y: groundY + lift,
                    width: legW, height: bodyBottom - groundY - lift
                )).fill()
            }

            // Eyes — transparent cutouts at the top of the angled body;
            // x-positions follow the full shear so they sit inside the parallelogram.
            NSGraphicsContext.current?.compositingOperation = .clear
            let eyeSize = px
            let eyeY    = bodyTopY - 1.5 * px
            NSBezierPath(rect: NSRect(x: bx + shear + px,     y: eyeY, width: eyeSize, height: eyeSize)).fill()
            NSBezierPath(rect: NSRect(x: bx + shear + 3 * px, y: eyeY, width: eyeSize, height: eyeSize)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawIdleFrame(phase: Double) -> NSImage {
        let size = frameSize  // 18×18
        let image = NSImage(size: size, flipped: false) { _ in
            let px: CGFloat = 2.0
            let cx: CGFloat = size.width / 2   // 9
            let groundY: CGFloat = 1.5
            let breathe = CGFloat(sin(phase * .pi * 2)) * 0.4

            NSColor.black.setFill()

            // Body: 6×3 px block (12×6 pt) — wide, squat rectangle matching the reference
            let bodyW = 6 * px   // 12 pt
            let bodyH = 5 * px   // 6 pt
            let bodyBottom = groundY + 1.5 * px + breathe
            let bodyRect = NSRect(x: cx - bodyW / 2, y: bodyBottom, width: bodyW, height: bodyH)
            NSBezierPath(rect: bodyRect).fill()

            // Arms: 1×2 px stubs centred vertically on the body sides
            let armW = 2 * px
            let armH = 2 * px
            let armY = bodyRect.minY + (bodyH - armH) / 2
            NSBezierPath(rect: NSRect(x: bodyRect.minX - armW, y: armY, width: armW, height: armH)).fill()
            NSBezierPath(rect: NSRect(x: bodyRect.maxX,        y: armY, width: armW, height: armH)).fill()

            // Legs: 4 legs, 1 px wide, evenly spaced, running from body bottom to ground
            let legW = px
            let gap = (bodyW - legW) / 3 // The total space available divided by the 3 gaps
            for i in 0...3 {
                let xPos = bodyRect.minX + CGFloat(i) * gap
                // let xPos = bodyRect.minX + CGFloat(i) * bodyW / 5 - legW / 2
                NSBezierPath(rect: NSRect(x: xPos, y: groundY, width: legW, height: bodyBottom - groundY)).fill()
            }

            // Eyes: transparent cutouts so the menu bar background shows through the black body
            NSGraphicsContext.current?.compositingOperation = .clear
            let eyeSize = px
            let eyeY = bodyRect.minY + bodyH - 1.5 * px
            let eyeL = NSRect(x: cx - 3.0 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)
            let eyeR = NSRect(x: cx + 3.0 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)

            let isBlinking = abs(phase - 0.5) < 0.1
            if isBlinking {
                NSBezierPath(rect: NSRect(x: eyeL.minX, y: eyeL.midY - 0.4, width: eyeSize, height: 0.8)).fill()
                NSBezierPath(rect: NSRect(x: eyeR.minX, y: eyeR.midY - 0.4, width: eyeSize, height: 0.8)).fill()
            } else {
                NSBezierPath(rect: eyeL).fill()
                NSBezierPath(rect: eyeR).fill()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Pack 2: Claude images

/// PNG-based sprite pack loaded from the `custom/` resource directory.
///
/// To add a new animation, append an entry to `clipDefinitions` below.
/// Frame files are named "claude1.png", "claude2.png", etc.
struct Clawd2Pack: SpritePack {
    let id = "clawd2"
    let displayName = "Clawd2"
    let frameSize = NSSize(width: 24, height: 18)

    /// Adjust this to change playback speed for this pack only.
    /// >1.0 = slower, <1.0 = faster. Default (1.0) matches SpeedMapper output.
    let frameIntervalScale: Double = 1.8

    /// Define all animation clips here.
    /// Each entry is (clipId, category, frameNumbers).
    /// Adding a new animation = one new line.
    private static let clipDefinitions: [(String, AnimationCategory, ClosedRange<Int>)] = [
        ("idle",  .idle, 1...6),
        ("run",   .run,  7...18),
    ]

    func clips() -> [AnimationClip] {
        Self.clipDefinitions.map { id, category, range in
            AnimationClip(id: id, category: category, frames: range.compactMap { loadFrame("claude\($0)") })
        }
    }

    private func loadFrame(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "custom"),
              let source = NSImage(contentsOf: url) else { return nil }
        let scaled = NSImage(size: frameSize, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        scaled.isTemplate = true
        return scaled
    }
}

// MARK: - Shared Drawing Utilities

/// Reusable drawing primitives shared across sprite packs.
enum SpriteDrawing {
    static func drawLeg(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, thickness: CGFloat = 2.2) {
        let path = NSBezierPath()
        path.lineWidth = thickness
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: fromX, y: fromY))
        path.line(to: NSPoint(x: toX, y: toY))
        NSColor.black.setStroke()
        path.stroke()
    }

    static func drawRoundedBody(centerX: CGFloat, bodyBottom: CGFloat, bodyHeight: CGFloat, bodyWidth: CGFloat, tilt: CGFloat = 0, squash: CGFloat = 1.0) {
        let adjustedHeight = bodyHeight * squash
        let adjustedWidth = bodyWidth * (1.0 + (1.0 - squash) * 0.3)
        let bodyRect = NSRect(x: centerX - adjustedWidth / 2 + tilt * 0.5, y: bodyBottom, width: adjustedWidth, height: adjustedHeight)
        let cornerRadius = min(adjustedWidth, adjustedHeight) * 0.4
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    static func drawFace(centerX: CGFloat, faceY: CGFloat, bodyWidth: CGFloat, lookDirection: CGFloat = 1.0) {
        let eyeRadius: CGFloat = 1.2
        let eyeOffsetX: CGFloat = bodyWidth * 0.12 * lookDirection
        let eyeRect = NSRect(x: centerX + eyeOffsetX - eyeRadius, y: faceY - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: eyeRect).fill()

        let sparkleRadius: CGFloat = 0.5
        let sparkleRect = NSRect(x: centerX + eyeOffsetX + lookDirection * 0.5 - sparkleRadius, y: faceY + 0.3 - sparkleRadius, width: sparkleRadius * 2, height: sparkleRadius * 2)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: sparkleRect).fill()
    }

    static func drawBlinkLine(centerX: CGFloat, faceY: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = 1.0
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: centerX - 1.5, y: faceY))
        path.line(to: NSPoint(x: centerX + 1.5, y: faceY))
        NSColor.white.setStroke()
        path.stroke()
    }
}
