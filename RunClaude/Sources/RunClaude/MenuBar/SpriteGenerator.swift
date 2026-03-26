import AppKit

// MARK: - Sprite Generator

/// Generates menu bar sprite frames programmatically.
///
/// The character is inspired by Claude's visual identity — a rounded,
/// friendly shape reminiscent of the Claude logo's warm aesthetic.
/// The body is a rounded capsule/bean shape with small legs and
/// a subtle "sparkle" eye. Drawn as template images so macOS
/// automatically adapts to light/dark menu bar.
struct SpriteGenerator {

    /// The size of each frame in points (menu bar standard height ~22pt, so 18pt with padding).
    static let frameSize = NSSize(width: 20, height: 18)

    /// Generate the running animation frames (smooth 10-frame run cycle).
    static func generateRunFrames(count: Int = 10) -> [NSImage] {
        (0..<count).map { frameIndex in
            let phase = Double(frameIndex) / Double(count)
            return drawRunFrame(phase: phase)
        }
    }

    /// Generate the idle animation frames (gentle breathing/bobbing).
    static func generateIdleFrames(count: Int = 6) -> [NSImage] {
        (0..<count).map { frameIndex in
            let phase = Double(frameIndex) / Double(count)
            return drawIdleFrame(phase: phase)
        }
    }

    // MARK: - Character Drawing Primitives

    /// Draw the Claude-inspired body shape: a rounded bean/capsule.
    /// `tilt` rotates the body slightly for run-cycle lean.
    /// `squash` compresses vertically (< 1.0) for bounce frames.
    private static func drawBody(
        in context: NSRect,
        centerX: CGFloat,
        bodyBottom: CGFloat,
        bodyHeight: CGFloat,
        bodyWidth: CGFloat,
        tilt: CGFloat = 0,
        squash: CGFloat = 1.0
    ) {
        let adjustedHeight = bodyHeight * squash
        let adjustedWidth = bodyWidth * (1.0 + (1.0 - squash) * 0.3) // stretch width when squashed

        // Rounded rectangle body (capsule shape)
        let bodyRect = NSRect(
            x: centerX - adjustedWidth / 2 + tilt * 0.5,
            y: bodyBottom,
            width: adjustedWidth,
            height: adjustedHeight
        )
        let cornerRadius = min(adjustedWidth, adjustedHeight) * 0.4
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.setFill()
        bodyPath.fill()
    }

    /// Draw the character's face: a simple dot eye and small highlight.
    private static func drawFace(
        centerX: CGFloat,
        faceY: CGFloat,
        bodyWidth: CGFloat,
        lookDirection: CGFloat = 1.0  // 1.0 = right, -1.0 = left
    ) {
        // Eye (small filled circle, offset in look direction)
        let eyeRadius: CGFloat = 1.2
        let eyeOffsetX: CGFloat = bodyWidth * 0.12 * lookDirection
        let eyeRect = NSRect(
            x: centerX + eyeOffsetX - eyeRadius,
            y: faceY - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        )

        // Draw the eye as a "cutout" (white circle on the dark body)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: eyeRect).fill()

        // Tiny sparkle/highlight dot
        let sparkleRadius: CGFloat = 0.5
        let sparkleRect = NSRect(
            x: centerX + eyeOffsetX + lookDirection * 0.5 - sparkleRadius,
            y: faceY + 0.3 - sparkleRadius,
            width: sparkleRadius * 2,
            height: sparkleRadius * 2
        )
        NSColor.black.setFill()
        NSBezierPath(ovalIn: sparkleRect).fill()
    }

    /// Draw small rounded legs.
    private static func drawLeg(
        fromX: CGFloat,
        fromY: CGFloat,
        toX: CGFloat,
        toY: CGFloat,
        thickness: CGFloat = 2.0
    ) {
        let path = NSBezierPath()
        path.lineWidth = thickness
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: fromX, y: fromY))
        path.line(to: NSPoint(x: toX, y: toY))
        NSColor.black.setStroke()
        path.stroke()
    }

    // MARK: - Run Cycle

    private static func drawRunFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let centerX: CGFloat = size.width / 2
            let bodyWidth: CGFloat = 10.0
            let bodyHeight: CGFloat = 9.0
            let legLength: CGFloat = 3.5

            // Run bounce: sinusoidal vertical motion
            let bounce = CGFloat(sin(phase * .pi * 2)) * 1.2
            let squash: CGFloat = 1.0 - abs(CGFloat(sin(phase * .pi * 2))) * 0.08

            // Forward lean during run
            let tilt = CGFloat(sin(phase * .pi * 2)) * 0.8

            let groundY: CGFloat = 1.5
            let bodyBottom = groundY + legLength + bounce

            // --- Legs (two legs, 180° out of phase) ---
            let legPhase1 = phase
            let legPhase2 = phase + 0.5

            // Leg 1: swing forward/back
            let leg1SwingX = CGFloat(sin(legPhase1 * .pi * 2)) * 3.5
            let leg1LiftY = max(0, CGFloat(sin(legPhase1 * .pi * 2))) * 1.5

            drawLeg(
                fromX: centerX - 1.5,
                fromY: bodyBottom + 1.0,
                toX: centerX - 1.5 + leg1SwingX,
                toY: groundY + leg1LiftY,
                thickness: 2.2
            )

            // Leg 2: opposite phase
            let leg2SwingX = CGFloat(sin(legPhase2 * .pi * 2)) * 3.5
            let leg2LiftY = max(0, CGFloat(sin(legPhase2 * .pi * 2))) * 1.5

            drawLeg(
                fromX: centerX + 1.5,
                fromY: bodyBottom + 1.0,
                toX: centerX + 1.5 + leg2SwingX,
                toY: groundY + leg2LiftY,
                thickness: 2.2
            )

            // --- Body ---
            drawBody(
                in: rect,
                centerX: centerX + tilt * 0.3,
                bodyBottom: bodyBottom,
                bodyHeight: bodyHeight,
                bodyWidth: bodyWidth,
                tilt: tilt,
                squash: squash
            )

            // --- Face ---
            let faceY = bodyBottom + bodyHeight * squash * 0.6
            drawFace(
                centerX: centerX + tilt * 0.3,
                faceY: faceY,
                bodyWidth: bodyWidth,
                lookDirection: 1.0  // always facing right while running
            )

            return true
        }

        image.isTemplate = true
        return image
    }

    // MARK: - Idle Animation

    private static func drawIdleFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let centerX: CGFloat = size.width / 2
            let bodyWidth: CGFloat = 10.0
            let bodyHeight: CGFloat = 9.0
            let legLength: CGFloat = 3.5

            // Gentle breathing: slow vertical bob
            let breathe = CGFloat(sin(phase * .pi * 2)) * 0.6
            // Subtle squash/stretch with breathing
            let squash: CGFloat = 1.0 + CGFloat(sin(phase * .pi * 2)) * 0.03

            let groundY: CGFloat = 1.5
            let bodyBottom = groundY + legLength + breathe

            // --- Legs (standing, slightly apart) ---
            drawLeg(
                fromX: centerX - 2.0,
                fromY: bodyBottom + 1.0,
                toX: centerX - 2.5,
                toY: groundY,
                thickness: 2.2
            )

            drawLeg(
                fromX: centerX + 2.0,
                fromY: bodyBottom + 1.0,
                toX: centerX + 2.5,
                toY: groundY,
                thickness: 2.2
            )

            // --- Body ---
            drawBody(
                in: rect,
                centerX: centerX,
                bodyBottom: bodyBottom,
                bodyHeight: bodyHeight,
                bodyWidth: bodyWidth,
                squash: squash
            )

            // --- Face ---
            let faceY = bodyBottom + bodyHeight * squash * 0.6

            // Blink: close eye briefly at phase ~0.75
            let blinkWindow = abs(phase - 0.75)
            let isBlinking = blinkWindow < 0.06

            if isBlinking {
                // Closed eye: horizontal line
                let eyeX = centerX
                let path = NSBezierPath()
                path.lineWidth = 1.0
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: eyeX - 1.5, y: faceY))
                path.line(to: NSPoint(x: eyeX + 1.5, y: faceY))
                NSColor.white.setStroke()
                path.stroke()
            } else {
                drawFace(
                    centerX: centerX,
                    faceY: faceY,
                    bodyWidth: bodyWidth,
                    lookDirection: 0.0  // looking straight ahead
                )
            }

            return true
        }

        image.isTemplate = true
        return image
    }
}
