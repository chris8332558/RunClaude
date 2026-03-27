import AppKit

// MARK: - Sprite Pack Protocol

/// A sprite pack provides run and idle animation frames.
/// Implement this to add new character styles.
protocol SpritePack {
    /// Unique identifier for this pack (used in UserDefaults).
    var id: String { get }
    /// Display name shown in Settings.
    var displayName: String { get }
    /// The size of each frame in points.
    var frameSize: NSSize { get }
    /// Generate the running animation frames.
    func generateRunFrames() -> [NSImage]
    /// Generate the idle animation frames.
    func generateIdleFrames() -> [NSImage]
}

// MARK: - Sprite Pack Registry

/// Central registry for all available sprite packs.
struct SpritePackRegistry {
    static let allPacks: [SpritePack] = [
        ClaudeBeanPack(),
        RunningCatPack(),
        PixelRobotPack(),
        NyanBarPack(),
        GhostPack()
    ]

    static let defaultPackId = "claude-bean"

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
struct ClaudeBeanPack: SpritePack {
    let id = "claude-bean"
    let displayName = "Claude Bean"
    let frameSize = NSSize(width: 20, height: 18)

    func generateRunFrames() -> [NSImage] {
        (0..<10).map { drawRunFrame(phase: Double($0) / 10.0) }
    }

    func generateIdleFrames() -> [NSImage] {
        (0..<6).map { drawIdleFrame(phase: Double($0) / 6.0) }
    }

    private func drawRunFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let centerX: CGFloat = size.width / 2
            let bodyWidth: CGFloat = 10.0
            let bodyHeight: CGFloat = 9.0
            let legLength: CGFloat = 3.5
            let bounce = CGFloat(sin(phase * .pi * 2)) * 1.2
            let squash: CGFloat = 1.0 - abs(CGFloat(sin(phase * .pi * 2))) * 0.08
            let tilt = CGFloat(sin(phase * .pi * 2)) * 0.8
            let groundY: CGFloat = 1.5
            let bodyBottom = groundY + legLength + bounce

            let legPhase1 = phase
            let legPhase2 = phase + 0.5
            let leg1SwingX = CGFloat(sin(legPhase1 * .pi * 2)) * 3.5
            let leg1LiftY = max(0, CGFloat(sin(legPhase1 * .pi * 2))) * 1.5
            SpriteDrawing.drawLeg(fromX: centerX - 1.5, fromY: bodyBottom + 1, toX: centerX - 1.5 + leg1SwingX, toY: groundY + leg1LiftY)
            let leg2SwingX = CGFloat(sin(legPhase2 * .pi * 2)) * 3.5
            let leg2LiftY = max(0, CGFloat(sin(legPhase2 * .pi * 2))) * 1.5
            SpriteDrawing.drawLeg(fromX: centerX + 1.5, fromY: bodyBottom + 1, toX: centerX + 1.5 + leg2SwingX, toY: groundY + leg2LiftY)

            SpriteDrawing.drawRoundedBody(centerX: centerX + tilt * 0.3, bodyBottom: bodyBottom, bodyHeight: bodyHeight, bodyWidth: bodyWidth, tilt: tilt, squash: squash)

            let faceY = bodyBottom + bodyHeight * squash * 0.6
            SpriteDrawing.drawFace(centerX: centerX + tilt * 0.3, faceY: faceY, bodyWidth: bodyWidth, lookDirection: 1.0)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawIdleFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let centerX: CGFloat = size.width / 2
            let bodyWidth: CGFloat = 10.0
            let bodyHeight: CGFloat = 9.0
            let legLength: CGFloat = 3.5
            let breathe = CGFloat(sin(phase * .pi * 2)) * 0.6
            let squash: CGFloat = 1.0 + CGFloat(sin(phase * .pi * 2)) * 0.03
            let groundY: CGFloat = 1.5
            let bodyBottom = groundY + legLength + breathe

            SpriteDrawing.drawLeg(fromX: centerX - 2.0, fromY: bodyBottom + 1, toX: centerX - 2.5, toY: groundY)
            SpriteDrawing.drawLeg(fromX: centerX + 2.0, fromY: bodyBottom + 1, toX: centerX + 2.5, toY: groundY)
            SpriteDrawing.drawRoundedBody(centerX: centerX, bodyBottom: bodyBottom, bodyHeight: bodyHeight, bodyWidth: bodyWidth, squash: squash)

            let faceY = bodyBottom + bodyHeight * squash * 0.6
            let isBlinking = abs(phase - 0.75) < 0.06
            if isBlinking {
                SpriteDrawing.drawBlinkLine(centerX: centerX, faceY: faceY)
            } else {
                SpriteDrawing.drawFace(centerX: centerX, faceY: faceY, bodyWidth: bodyWidth, lookDirection: 0)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Pack 2: Running Cat

/// A small cat silhouette with a wavy tail.
struct RunningCatPack: SpritePack {
    let id = "running-cat"
    let displayName = "Running Cat"
    let frameSize = NSSize(width: 22, height: 18)

    func generateRunFrames() -> [NSImage] {
        (0..<8).map { drawRunFrame(phase: Double($0) / 8.0) }
    }

    func generateIdleFrames() -> [NSImage] {
        (0..<6).map { drawIdleFrame(phase: Double($0) / 6.0) }
    }

    private func drawRunFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let groundY: CGFloat = 2.0
            let bodyY: CGFloat = groundY + 5 + CGFloat(sin(phase * .pi * 2)) * 1.5
            let bodyLen: CGFloat = 10.0
            let bodyLeft: CGFloat = 4.0
            let bodyMidX: CGFloat = bodyLeft + bodyLen / 2
            let bodyRight: CGFloat = bodyLeft + bodyLen

            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Body (oval)
            let bodyRect = NSRect(x: bodyLeft, y: bodyY, width: bodyLen, height: 5.5)
            NSBezierPath(ovalIn: bodyRect).fill()

            // Head (circle)
            let headR: CGFloat = 3.5
            let headRect = NSRect(x: bodyRight - 2, y: bodyY + 2, width: headR * 2, height: headR * 2)
            NSBezierPath(ovalIn: headRect).fill()

            // Ears (triangles)
            for dx: CGFloat in [1.5, 4.5] {
                let ear = NSBezierPath()
                ear.move(to: NSPoint(x: bodyRight - 2 + dx, y: bodyY + 2 + headR * 2))
                ear.line(to: NSPoint(x: bodyRight - 2 + dx - 1, y: bodyY + 2 + headR * 2 + 3))
                ear.line(to: NSPoint(x: bodyRight - 2 + dx + 1, y: bodyY + 2 + headR * 2 + 3))
                ear.close()
                ear.fill()
            }

            // Legs (4 legs, paired 180° out of phase)
            let legSwing1 = CGFloat(sin(phase * .pi * 2)) * 3.0
            let legSwing2 = CGFloat(sin((phase + 0.5) * .pi * 2)) * 3.0
            let legY = bodyY - 0.5

            for (x, swing) in [(bodyLeft + 2, legSwing1), (bodyLeft + 3.5, legSwing2),
                                (bodyRight - 3.5, legSwing2), (bodyRight - 2, legSwing1)] {
                let leg = NSBezierPath()
                leg.lineWidth = 1.8
                leg.lineCapStyle = .round
                leg.move(to: NSPoint(x: x, y: legY))
                leg.line(to: NSPoint(x: x + swing, y: groundY))
                leg.stroke()
            }

            // Tail (curved, waving)
            let tailWave = CGFloat(sin(phase * .pi * 2 + 1)) * 2.5
            let tail = NSBezierPath()
            tail.lineWidth = 1.8
            tail.lineCapStyle = .round
            tail.move(to: NSPoint(x: bodyLeft, y: bodyY + 3))
            tail.curve(
                to: NSPoint(x: bodyLeft - 5, y: bodyY + 6 + tailWave),
                controlPoint1: NSPoint(x: bodyLeft - 2, y: bodyY + 2),
                controlPoint2: NSPoint(x: bodyLeft - 4, y: bodyY + 5 + tailWave * 0.5)
            )
            tail.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawIdleFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let groundY: CGFloat = 2.0
            let bodyY: CGFloat = groundY + 4
            let bodyLen: CGFloat = 10.0
            let bodyLeft: CGFloat = 4.0
            let bodyRight: CGFloat = bodyLeft + bodyLen

            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Body (sitting, more upright)
            let bodyRect = NSRect(x: bodyLeft + 1, y: bodyY, width: bodyLen - 2, height: 6)
            NSBezierPath(ovalIn: bodyRect).fill()

            // Head
            let headR: CGFloat = 3.5
            let headRect = NSRect(x: bodyRight - 3, y: bodyY + 3, width: headR * 2, height: headR * 2)
            NSBezierPath(ovalIn: headRect).fill()

            // Ears
            for dx: CGFloat in [1.5, 4.5] {
                let ear = NSBezierPath()
                ear.move(to: NSPoint(x: bodyRight - 3 + dx, y: bodyY + 3 + headR * 2))
                ear.line(to: NSPoint(x: bodyRight - 3 + dx - 1, y: bodyY + 3 + headR * 2 + 3))
                ear.line(to: NSPoint(x: bodyRight - 3 + dx + 1, y: bodyY + 3 + headR * 2 + 3))
                ear.close()
                ear.fill()
            }

            // Front legs (sitting)
            for x: CGFloat in [bodyLeft + 3, bodyLeft + 5] {
                let leg = NSBezierPath()
                leg.lineWidth = 1.8
                leg.lineCapStyle = .round
                leg.move(to: NSPoint(x: x, y: bodyY))
                leg.line(to: NSPoint(x: x, y: groundY))
                leg.stroke()
            }

            // Tail (gentle wave)
            let tailWave = CGFloat(sin(phase * .pi * 2)) * 1.5
            let tail = NSBezierPath()
            tail.lineWidth = 1.8
            tail.lineCapStyle = .round
            tail.move(to: NSPoint(x: bodyLeft + 1, y: bodyY + 2))
            tail.curve(
                to: NSPoint(x: bodyLeft - 4, y: bodyY + 4 + tailWave),
                controlPoint1: NSPoint(x: bodyLeft - 1, y: bodyY + 1),
                controlPoint2: NSPoint(x: bodyLeft - 3, y: bodyY + 3 + tailWave * 0.5)
            )
            tail.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Pack 3: Pixel Robot

/// A blocky pixel-art robot with antenna.
struct PixelRobotPack: SpritePack {
    let id = "pixel-robot"
    let displayName = "Pixel Robot"
    let frameSize = NSSize(width: 18, height: 18)

    func generateRunFrames() -> [NSImage] {
        (0..<8).map { drawRunFrame(phase: Double($0) / 8.0) }
    }

    func generateIdleFrames() -> [NSImage] {
        (0..<4).map { drawIdleFrame(phase: Double($0) / 4.0) }
    }

    private func drawRunFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let px: CGFloat = 2.0 // pixel size
            let centerX: CGFloat = size.width / 2
            let bounce = CGFloat(sin(phase * .pi * 2)) * 1.0
            let groundY: CGFloat = 1.0

            NSColor.black.setFill()

            // Legs (alternating)
            let legSwing = CGFloat(sin(phase * .pi * 2)) * 2.0
            // Left leg
            NSBezierPath(rect: NSRect(x: centerX - 3 * px + legSwing, y: groundY, width: px, height: 3 * px)).fill()
            // Right leg
            NSBezierPath(rect: NSRect(x: centerX + 1 * px - legSwing, y: groundY, width: px, height: 3 * px)).fill()

            let bodyBottom = groundY + 3 * px + bounce

            // Body (rectangle)
            NSBezierPath(rect: NSRect(x: centerX - 3 * px, y: bodyBottom, width: 6 * px, height: 4 * px)).fill()

            // Arms
            let armSwing = CGFloat(sin(phase * .pi * 2)) * 1.5
            NSBezierPath(rect: NSRect(x: centerX - 4 * px, y: bodyBottom + px - armSwing, width: px, height: 2 * px)).fill()
            NSBezierPath(rect: NSRect(x: centerX + 3 * px, y: bodyBottom + px + armSwing, width: px, height: 2 * px)).fill()

            // Head
            let headBottom = bodyBottom + 4 * px
            NSBezierPath(rect: NSRect(x: centerX - 2.5 * px, y: headBottom, width: 5 * px, height: 3 * px)).fill()

            // Eyes (cutout)
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: centerX - 1.5 * px, y: headBottom + px, width: px, height: px)).fill()
            NSBezierPath(rect: NSRect(x: centerX + 0.5 * px, y: headBottom + px, width: px, height: px)).fill()

            // Antenna
            NSColor.black.setFill()
            let antennaWave = CGFloat(sin(phase * .pi * 4)) * 0.5
            NSBezierPath(rect: NSRect(x: centerX - 0.25 * px, y: headBottom + 3 * px, width: 0.5 * px, height: 2 * px)).fill()
            NSBezierPath(ovalIn: NSRect(x: centerX - 0.75 * px + antennaWave, y: headBottom + 5 * px, width: 1.5 * px, height: 1.5 * px)).fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawIdleFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let px: CGFloat = 2.0
            let centerX: CGFloat = size.width / 2
            let groundY: CGFloat = 1.0

            NSColor.black.setFill()

            // Legs (standing)
            NSBezierPath(rect: NSRect(x: centerX - 2.5 * px, y: groundY, width: px, height: 3 * px)).fill()
            NSBezierPath(rect: NSRect(x: centerX + 1.5 * px, y: groundY, width: px, height: 3 * px)).fill()

            let bodyBottom = groundY + 3 * px

            // Body
            NSBezierPath(rect: NSRect(x: centerX - 3 * px, y: bodyBottom, width: 6 * px, height: 4 * px)).fill()

            // Arms (down)
            NSBezierPath(rect: NSRect(x: centerX - 4 * px, y: bodyBottom, width: px, height: 2 * px)).fill()
            NSBezierPath(rect: NSRect(x: centerX + 3 * px, y: bodyBottom, width: px, height: 2 * px)).fill()

            // Head
            let headBottom = bodyBottom + 4 * px
            NSBezierPath(rect: NSRect(x: centerX - 2.5 * px, y: headBottom, width: 5 * px, height: 3 * px)).fill()

            // Eyes (blink every other frame)
            NSColor.white.setFill()
            let isBlinking = abs(phase - 0.5) < 0.15
            if isBlinking {
                NSBezierPath(rect: NSRect(x: centerX - 1.5 * px, y: headBottom + px, width: px, height: 0.3 * px)).fill()
                NSBezierPath(rect: NSRect(x: centerX + 0.5 * px, y: headBottom + px, width: px, height: 0.3 * px)).fill()
            } else {
                NSBezierPath(rect: NSRect(x: centerX - 1.5 * px, y: headBottom + px, width: px, height: px)).fill()
                NSBezierPath(rect: NSRect(x: centerX + 0.5 * px, y: headBottom + px, width: px, height: px)).fill()
            }

            // Antenna (gentle bob)
            NSColor.black.setFill()
            let bob = CGFloat(sin(phase * .pi * 2)) * 0.5
            NSBezierPath(rect: NSRect(x: centerX - 0.25 * px, y: headBottom + 3 * px, width: 0.5 * px, height: 2 * px)).fill()
            NSBezierPath(ovalIn: NSRect(x: centerX - 0.75 * px, y: headBottom + 5 * px + bob, width: 1.5 * px, height: 1.5 * px)).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Pack 4: Nyan Bar

/// A simple bouncing bar/wave inspired by audio visualizers.
struct NyanBarPack: SpritePack {
    let id = "nyan-bar"
    let displayName = "Sound Wave"
    let frameSize = NSSize(width: 20, height: 18)

    func generateRunFrames() -> [NSImage] {
        (0..<12).map { drawFrame(phase: Double($0) / 12.0, amplitude: 1.0) }
    }

    func generateIdleFrames() -> [NSImage] {
        (0..<6).map { drawFrame(phase: Double($0) / 6.0, amplitude: 0.3) }
    }

    private func drawFrame(phase: Double, amplitude: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { rect in
            let barCount = 5
            let barWidth: CGFloat = 2.5
            let gap: CGFloat = 1.0
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (size.width - totalWidth) / 2
            let baseHeight: CGFloat = 3.0
            let maxHeight: CGFloat = 14.0

            NSColor.black.setFill()

            for i in 0..<barCount {
                let barPhase = phase + Double(i) * 0.2
                let height = baseHeight + (maxHeight - baseHeight) * CGFloat(amplitude) * CGFloat((sin(barPhase * .pi * 2) + 1) / 2)
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = (size.height - height) / 2

                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Pack 5: Ghost

/// A cute floating ghost with a rounded head, straight sides, and a 3-bump wavy skirt.
struct GhostPack: SpritePack {
    let id = "ghost"
    let displayName = "Ghost"
    let frameSize = NSSize(width: 18, height: 18)

    func generateRunFrames() -> [NSImage] {
        (0..<8).map { drawRunFrame(phase: Double($0) / 8.0) }
    }

    func generateIdleFrames() -> [NSImage] {
        (0..<6).map { drawIdleFrame(phase: Double($0) / 6.0) }
    }

    // Draws the ghost body + eyes. bodyBottom is the lowest point of the wavy skirt.
    private func drawGhostBody(centerX: CGFloat, bodyBottom: CGFloat, tilt: CGFloat = 0, blinking: Bool = false) {
        let bodyW: CGFloat = 12.0
        let radius: CGFloat = bodyW / 2       // 6 — radius of the rounded head
        let sideH: CGFloat = 6.0             // height of the straight-sided torso section
        let left  = centerX - radius + tilt
        let right = centerX + radius + tilt
        let skirtY     = bodyBottom + 2       // where bumps join the body sides
        let arcCenterY = skirtY + sideH       // centre of the semicircular head

        // --- body + skirt ---
        NSColor.black.setFill()
        let ghost = NSBezierPath()
        ghost.move(to: NSPoint(x: left, y: arcCenterY))
        // Rounded top: counterclockwise arc from 180° (left) through 90° (top) to 0° (right)
        ghost.appendArc(
            withCenter: NSPoint(x: centerX + tilt, y: arcCenterY),
            radius: radius,
            startAngle: 180,
            endAngle: 0,
            clockwise: false
        )
        ghost.line(to: NSPoint(x: right, y: skirtY))

        // Three downward bumps from right to left, each bodyW/3 wide, peaking at bodyBottom
        let bw = bodyW / 3
        let peakY = bodyBottom
        ghost.curve(
            to: NSPoint(x: right - bw, y: skirtY),
            controlPoint1: NSPoint(x: right - bw * 0.3, y: peakY),
            controlPoint2: NSPoint(x: right - bw * 0.7, y: peakY)
        )
        ghost.curve(
            to: NSPoint(x: left + bw, y: skirtY),
            controlPoint1: NSPoint(x: right - bw * 1.25, y: peakY),
            controlPoint2: NSPoint(x: left  + bw * 1.25, y: peakY)
        )
        ghost.curve(
            to: NSPoint(x: left, y: skirtY),
            controlPoint1: NSPoint(x: left + bw * 0.7, y: peakY),
            controlPoint2: NSPoint(x: left + bw * 0.3, y: peakY)
        )
        ghost.close()
        ghost.fill()

        // --- eyes (white, set against the black body) ---
        let eyeY = arcCenterY + 1.0
        NSColor.white.setFill()
        if blinking {
            NSColor.white.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.0
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: centerX + tilt - 3.5, y: eyeY))
            path.line(to: NSPoint(x: centerX + tilt - 1.2, y: eyeY))
            path.move(to: NSPoint(x: centerX + tilt + 1.2, y: eyeY))
            path.line(to: NSPoint(x: centerX + tilt + 3.5, y: eyeY))
            path.stroke()
        } else {
            NSBezierPath(ovalIn: NSRect(x: centerX + tilt - 4.0, y: eyeY - 1.2, width: 2.4, height: 2.4)).fill()
            NSBezierPath(ovalIn: NSRect(x: centerX + tilt + 1.6, y: eyeY - 1.2, width: 2.4, height: 2.4)).fill()
        }
    }

    private func drawRunFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { _ in
            let centerX = size.width / 2
            let bob  = CGFloat(sin(phase * .pi * 2)) * 1.5
            let tilt = CGFloat(sin(phase * .pi * 2)) * 0.6
            self.drawGhostBody(centerX: centerX, bodyBottom: 2.5 + bob, tilt: tilt)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawIdleFrame(phase: Double) -> NSImage {
        let size = frameSize
        let image = NSImage(size: size, flipped: false) { _ in
            let centerX = size.width / 2
            let bob = CGFloat(sin(phase * .pi * 2)) * 0.8
            let isBlinking = abs(phase - 0.85) < 0.08
            self.drawGhostBody(centerX: centerX, bodyBottom: 3.0 + bob, blinking: isBlinking)
            return true
        }
        image.isTemplate = true
        return image
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
