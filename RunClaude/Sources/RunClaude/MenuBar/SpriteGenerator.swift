import AppKit

// MARK: - Sprite Generator

/// Generates menu bar sprite frames programmatically.
///
/// Phase 1 uses procedural drawing (no external image assets needed).
/// The sprites are drawn as template images so macOS automatically
/// adapts them to light/dark menu bar.
///
/// Replace this with hand-crafted or AI-generated sprite sheets in Phase 3.
struct SpriteGenerator {

    /// The size of each frame in points.
    static let frameSize = NSSize(width: 18, height: 18)

    /// Generate the running animation frames.
    /// Returns an array of NSImage template images forming a run cycle.
    static func generateRunFrames(count: Int = 8) -> [NSImage] {
        (0..<count).map { frameIndex in
            let phase = Double(frameIndex) / Double(count)
            return drawRunFrame(phase: phase)
        }
    }

    /// Generate the idle animation frames (gentle floating/breathing).
    static func generateIdleFrames(count: Int = 4) -> [NSImage] {
        (0..<count).map { frameIndex in
            let phase = Double(frameIndex) / Double(count)
            return drawIdleFrame(phase: phase)
        }
    }

    // MARK: - Run Cycle Drawing

    /// Draw a single frame of the run cycle.
    /// The character is a simple stick figure with a round head,
    /// with leg and arm positions varying by phase.
    private static func drawRunFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let scale: CGFloat = 1.0

            // Body proportions (in points, from bottom)
            let groundY: CGFloat = 2
            let bodyHeight: CGFloat = 6
            let headRadius: CGFloat = 3.0
            let centerX: CGFloat = size.width / 2

            // Bounce: body moves up/down slightly with run cycle
            let bounce = CGFloat(sin(phase * .pi * 2)) * 1.0
            let hipY = groundY + 4 + bounce
            let shoulderY = hipY + bodyHeight
            let headY = shoulderY + headRadius + 0.5

            let color = NSColor.black

            // --- Head (circle) ---
            let headRect = NSRect(
                x: centerX - headRadius,
                y: headY - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
            let headPath = NSBezierPath(ovalIn: headRect)
            color.setFill()
            headPath.fill()

            // --- Body (line from shoulder to hip) ---
            let bodyPath = NSBezierPath()
            bodyPath.lineWidth = 1.5 * scale
            bodyPath.move(to: NSPoint(x: centerX, y: shoulderY))
            bodyPath.line(to: NSPoint(x: centerX, y: hipY))
            color.setStroke()
            bodyPath.stroke()

            // --- Legs ---
            // Two legs, 180 degrees out of phase
            let legLength: CGFloat = 4.5
            let legSwing = CGFloat(sin(phase * .pi * 2)) * 3.0

            let leg1Path = NSBezierPath()
            leg1Path.lineWidth = 1.5 * scale
            leg1Path.move(to: NSPoint(x: centerX, y: hipY))
            leg1Path.line(to: NSPoint(x: centerX + legSwing, y: hipY - legLength))
            color.setStroke()
            leg1Path.stroke()

            let leg2Path = NSBezierPath()
            leg2Path.lineWidth = 1.5 * scale
            leg2Path.move(to: NSPoint(x: centerX, y: hipY))
            leg2Path.line(to: NSPoint(x: centerX - legSwing, y: hipY - legLength))
            leg2Path.stroke()

            // --- Arms ---
            let armLength: CGFloat = 3.5
            let armSwing = CGFloat(sin(phase * .pi * 2)) * 2.5

            let arm1Path = NSBezierPath()
            arm1Path.lineWidth = 1.2 * scale
            arm1Path.move(to: NSPoint(x: centerX, y: shoulderY - 1))
            arm1Path.line(to: NSPoint(x: centerX - armSwing, y: shoulderY - 1 - armLength))
            arm1Path.stroke()

            let arm2Path = NSBezierPath()
            arm2Path.lineWidth = 1.2 * scale
            arm2Path.move(to: NSPoint(x: centerX, y: shoulderY - 1))
            arm2Path.line(to: NSPoint(x: centerX + armSwing, y: shoulderY - 1 - armLength))
            arm2Path.stroke()

            return true
        }

        image.isTemplate = true
        return image
    }

    // MARK: - Idle Drawing

    /// Draw a single frame of the idle animation.
    /// A standing figure with a gentle "breathing" sway.
    private static func drawIdleFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let centerX: CGFloat = size.width / 2
            let groundY: CGFloat = 2
            let bodyHeight: CGFloat = 6
            let headRadius: CGFloat = 3.0

            // Gentle breathing motion
            let breathe = CGFloat(sin(phase * .pi * 2)) * 0.5

            let hipY = groundY + 4
            let shoulderY = hipY + bodyHeight + breathe
            let headY = shoulderY + headRadius + 0.5

            let color = NSColor.black

            // Head
            let headRect = NSRect(
                x: centerX - headRadius,
                y: headY - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
            NSBezierPath(ovalIn: headRect).fill()

            // Body
            let bodyPath = NSBezierPath()
            bodyPath.lineWidth = 1.5
            bodyPath.move(to: NSPoint(x: centerX, y: shoulderY))
            bodyPath.line(to: NSPoint(x: centerX, y: hipY))
            color.setStroke()
            bodyPath.stroke()

            // Legs (standing straight, slightly apart)
            let legLength: CGFloat = 4.5

            let leg1 = NSBezierPath()
            leg1.lineWidth = 1.5
            leg1.move(to: NSPoint(x: centerX, y: hipY))
            leg1.line(to: NSPoint(x: centerX - 1.5, y: hipY - legLength))
            leg1.stroke()

            let leg2 = NSBezierPath()
            leg2.lineWidth = 1.5
            leg2.move(to: NSPoint(x: centerX, y: hipY))
            leg2.line(to: NSPoint(x: centerX + 1.5, y: hipY - legLength))
            leg2.stroke()

            // Arms (relaxed at sides)
            let armLength: CGFloat = 3.5
            let armSway = CGFloat(sin(phase * .pi * 2)) * 0.3

            let arm1 = NSBezierPath()
            arm1.lineWidth = 1.2
            arm1.move(to: NSPoint(x: centerX, y: shoulderY - 1))
            arm1.line(to: NSPoint(x: centerX - 2.5 - armSway, y: shoulderY - 1 - armLength))
            arm1.stroke()

            let arm2 = NSBezierPath()
            arm2.lineWidth = 1.2
            arm2.move(to: NSPoint(x: centerX, y: shoulderY - 1))
            arm2.line(to: NSPoint(x: centerX + 2.5 + armSway, y: shoulderY - 1 - armLength))
            arm2.stroke()

            return true
        }

        image.isTemplate = true
        return image
    }
}
