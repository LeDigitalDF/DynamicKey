// LeakPeekSonarRadarView.swift
// GPU-drawn sonar radar for email breach checks — grid, rotating sweep, and dynamic blips.
// Flow: TimelineView ticks → Canvas redraws grid + sweep wedge + blips that glow on beam pass.

import SwiftUI

struct LeakPeekSonarRadarView: View {
    let blips: [LeakPeekRadarBlip]
    let progress: Double

    private let sonarGreen = Color(red: 0.12, green: 0.92, blue: 0.52)
    private let sonarGlow = Color(red: 0.2, green: 1.0, blue: 0.62)

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                Canvas { context, size in
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                    let radius = min(size.width, size.height) * 0.5 - 10
                    let sweepAngle = timeline.date.timeIntervalSinceReferenceDate * 1.15

                    drawGrid(in: &context, center: center, radius: radius)
                    drawSweep(in: &context, center: center, radius: radius, sweepAngle: sweepAngle)
                    drawBlips(
                        in: &context,
                        center: center,
                        radius: radius,
                        sweepAngle: sweepAngle
                    )
                }
            }

            VStack(spacing: 4) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(sonarGlow)
                    .monospacedDigit()

                Text("SCANNING")
                    .font(.caption2.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(sonarGreen.opacity(0.75))
            }
            .allowsHitTesting(false)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Breach scan in progress, \(Int((progress * 100).rounded())) percent complete")
    }

    // Concentric rings and crosshairs for the sonar grid.
    private func drawGrid(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for ring in 1...4 {
            let ringRadius = radius * CGFloat(ring) / 4
            let rect = CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(sonarGreen.opacity(ring == 4 ? 0.42 : 0.2)),
                lineWidth: ring == 4 ? 1.2 : 0.8
            )
        }

        var crosshair = Path()
        crosshair.move(to: CGPoint(x: center.x - radius, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - radius))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        context.stroke(crosshair, with: .color(sonarGreen.opacity(0.22)), lineWidth: 0.8)

        let hubRadius: CGFloat = 4
        let hub = Path(ellipseIn: CGRect(
            x: center.x - hubRadius,
            y: center.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        ))
        context.fill(hub, with: .color(sonarGlow.opacity(0.9)))
    }

    // Rotating sweep wedge — solid at the leading edge, fading to transparent behind.
    private func drawSweep(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        sweepAngle: Double
    ) {
        let wedgeSpan = Double.pi * 0.38
        let segmentCount = 28

        for index in 0..<segmentCount {
            let fraction = Double(index) / Double(segmentCount)
            let start = sweepAngle - wedgeSpan + (wedgeSpan * fraction)
            let end = start + (wedgeSpan / Double(segmentCount))
            let opacity = fraction * 0.42

            var slice = Path()
            slice.move(to: center)
            slice.addArc(
                center: center,
                radius: radius,
                startAngle: .radians(start),
                endAngle: .radians(end),
                clockwise: false
            )
            slice.closeSubpath()
            context.fill(slice, with: .color(sonarGreen.opacity(opacity)))
        }

        var beam = Path()
        beam.move(to: center)
        beam.addLine(to: CGPoint(
            x: center.x + CGFloat(cos(sweepAngle)) * radius,
            y: center.y + CGFloat(sin(sweepAngle)) * radius
        ))
        context.stroke(beam, with: .color(sonarGlow.opacity(0.95)), lineWidth: 1.6)
    }

    // Email blips — brighten when the sweep passes; compromised blips use orange.
    private func drawBlips(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        sweepAngle: Double
    ) {
        for blip in blips {
            let point = CGPoint(
                x: center.x + CGFloat(cos(blip.angle)) * radius * blip.distance,
                y: center.y + CGFloat(sin(blip.angle)) * radius * blip.distance
            )

            let glow = sweepGlow(for: blip.angle, sweepAngle: sweepAngle)
            let baseOpacity = blip.isChecked ? 0.35 : 0.14
            let opacity = min(1, baseOpacity + glow * 0.75)
            let blipColor: Color = {
                if !blip.isChecked { return sonarGreen }
                return blip.isCompromised
                    ? Color(red: 1.0, green: 0.55, blue: 0.18)
                    : sonarGlow
            }()

            let outer = Path(ellipseIn: CGRect(
                x: point.x - 7,
                y: point.y - 7,
                width: 14,
                height: 14
            ))
            context.fill(outer, with: .color(blipColor.opacity(opacity * 0.35)))

            let core = Path(ellipseIn: CGRect(
                x: point.x - 3.5,
                y: point.y - 3.5,
                width: 7,
                height: 7
            ))
            context.fill(core, with: .color(blipColor.opacity(opacity)))
        }
    }

    // Returns 0…1 based on how close the sweep is to a blip angle.
    private func sweepGlow(for blipAngle: Double, sweepAngle: Double) -> Double {
        var delta = abs(blipAngle - sweepAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta = (2 * .pi) - delta }
        return max(0, 1 - (delta / 0.55))
    }
}
