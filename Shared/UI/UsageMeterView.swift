import Charts
import SwiftUI

/// Renders a single ``UsageLimit`` in the user's chosen ``UsageChartStyle``.
/// Shared by the app overview (roomy) and the widget (`compact`), so both
/// surfaces stay visually consistent when the style changes in Settings.
struct UsageMeterView: View {
    let limit: UsageLimit
    var style: UsageChartStyle = .progressBar
    var compact: Bool = false
    /// The app shows a reset caption; the widget hides it to save space.
    var showReset: Bool = false

    var body: some View {
        switch style {
        case .progressBar:
            progressBarBody
        case .bar:
            barBody
        case .donut:
            donutBody
        case .waterBall:
            waterBallBody
        case .neonSegments:
            neonSegmentsBody
        }
    }

    // MARK: - Styles

    private var progressBarBody: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            header
            // Explicit-fill capsule instead of `ProgressView`: the system-drawn
            // ProgressView loses its tint and renders all-gray when the widget
            // is inactive (desaturated rendering). Explicit fills survive it.
            MeterBar(fraction: clampedPercent / 100, tint: tint, height: compact ? 6 : 9)
            resetView
        }
    }

    private var barBody: some View {
        HStack(spacing: compact ? 8 : 14) {
            // Vertical bar filled from the bottom — visually distinct from the
            // linear progress bar. "Used" stacks below the muted "remaining".
            Chart(segments) { segment in
                BarMark(
                    x: .value("Limit", "usage"),
                    y: .value("Percent", segment.value)
                )
                .foregroundStyle(segment.color)
                .cornerRadius(compact ? 2 : 3)
            }
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .frame(width: compact ? 16 : 26, height: compact ? 38 : 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(limit.label)
                    .font(compact ? .caption2 : .headline)
                    .lineLimit(1)
                Text(percentText)
                    .font(compact ? .caption2 : .subheadline)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                resetView
            }
            Spacer(minLength: 0)
        }
    }

    private var donutBody: some View {
        HStack(spacing: compact ? 8 : 14) {
            ZStack {
                Chart(segments) { segment in
                    SectorMark(
                        angle: .value("Percent", segment.value),
                        innerRadius: .ratio(compact ? 0.66 : 0.62),
                        angularInset: 1
                    )
                    .foregroundStyle(segment.color)
                    .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .frame(width: diameter, height: diameter)

                Text(UsageDisplayFormatting.shortPercentText(limit.percent))
                    .font(compact ? .system(size: 11, weight: .bold) : .headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(limit.label)
                    .font(compact ? .caption2 : .headline)
                    .lineLimit(1)
                resetView
            }
            Spacer(minLength: 0)
        }
    }

    private var waterBallBody: some View {
        HStack(spacing: compact ? 8 : 14) {
            WaterBallView(
                remaining: CGFloat(remainingPercent / 100),
                tint: tint,
                animated: !compact
            )
            .frame(width: diameter, height: diameter)
            .overlay(
                Text("\(Int(remainingPercent.rounded()))%")
                    .font(compact ? .system(size: 11, weight: .bold) : .headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.15), radius: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(limit.label)
                    .font(compact ? .caption2 : .headline)
                    .lineLimit(1)
                if !compact {
                    Text("\(Int(remainingPercent.rounded()))% left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    resetView
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var neonSegmentsBody: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            header
            NeonSegmentGaugeView(
                fraction: clampedPercent / 100,
                compact: compact
            )
            resetView
        }
    }

    // MARK: - Shared pieces

    private var header: some View {
        HStack {
            Text(limit.label)
                .font(compact ? .caption2 : .headline)
                .lineLimit(1)
            Spacer()
            Text(percentText)
                .font(compact ? .caption2 : .body)
                .bold()
                .monospacedDigit()
                .foregroundStyle(compact ? .primary : .secondary)
        }
    }

    /// Reset countdown: a thin depleting bar (full = window just started,
    /// empty = reset due) paired with a "resets in 3d 5h" caption. The bar is
    /// only drawn when the window length for this limit is known.
    @ViewBuilder
    private var resetView: some View {
        if showReset, let countdown = UsageDisplayFormatting.resetCountdownText(for: limit.resetsAt) {
            VStack(alignment: .leading, spacing: 2) {
                if let fraction = UsageDisplayFormatting.resetRemainingFraction(
                    for: limit.resetsAt,
                    window: resetWindow
                ) {
                    MeterBar(fraction: fraction, tint: .accentColor, height: 3)
                }
                Text(countdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Length of the rolling reset window for this limit, inferred from its
    /// kind. Used to turn a bare reset timestamp into a countdown fraction.
    private var resetWindow: TimeInterval? {
        switch limit.kind {
        case "session": return 5 * 3600
        case "weekly_all", "weekly_scoped": return 7 * 86_400
        case "codex_primary": return 5 * 3600
        case "codex_secondary": return 7 * 86_400
        default: return nil
        }
    }

    // MARK: - Helpers

    private var clampedPercent: Double { UsageDisplayFormatting.clampedPercent(limit.percent) }

    /// Percentage of the quota still available (used by the water ball).
    private var remainingPercent: Double { max(0, 100 - clampedPercent) }

    private var percentText: String {
        compact ? UsageDisplayFormatting.shortPercentText(limit.percent)
                : UsageDisplayFormatting.percentText(limit.percent)
    }

    private var diameter: CGFloat { compact ? 36 : 64 }

    /// Traffic-light tint that intensifies as usage climbs.
    private var tint: Color {
        switch clampedPercent {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }

    /// Used vs. remaining slices for the bar and donut charts.
    private var segments: [MeterSegment] {
        let used = clampedPercent
        return [
            MeterSegment(id: 0, name: "Used", value: used, color: tint),
            MeterSegment(id: 1, name: "Remaining", value: max(0, 100 - used), color: Color.secondary.opacity(0.18))
        ]
    }
}

/// A horizontal capsule progress bar drawn with explicit fills. Unlike
/// `ProgressView`, its colors don't wash out to gray when a widget is rendered
/// in its inactive (desaturated) state.
private struct MeterBar: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                Capsule()
                    .fill(tint)
                    .frame(width: min(max(fraction, 0), 1) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

private struct MeterSegment: Identifiable {
    let id: Int
    let name: String
    let value: Double
    let color: Color
}

/// A neon, slanted segment gauge inspired by arcade stat meters. It keeps the
/// percentage readable while giving the chart style a clearly different shape.
private struct NeonSegmentGaugeView: View {
    var fraction: Double
    var compact: Bool

    private var clampedFraction: Double { min(max(fraction, 0), 1) }
    private var segmentCount: Int { compact ? 14 : 22 }
    private var activeCount: Int { Int((clampedFraction * Double(segmentCount)).rounded()) }
    private var greenTailCount: Int { max(1, min(activeCount, compact ? 2 : 4)) }

    var body: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, compact ? 12 : 18)
            let slant = min(height * 0.46, compact ? 6 : 8)
            let leadWidth = min(max(geo.size.width * 0.28, compact ? 26 : 56), compact ? 44 : 92)
            let gap: CGFloat = compact ? 2 : 3
            let segmentWidth = max(
                compact ? 5 : 8,
                (geo.size.width - leadWidth - gap * CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
            )

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: leadWidth + slant, height: compact ? 3 : 4)
                    .offset(y: height * 0.22)

                HStack(spacing: gap) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        let isActive = index < activeCount
                        let isGreenTail = isActive && index >= max(0, activeCount - greenTailCount)
                        SlantedSegment(slant: slant)
                            .fill(segmentColor(isActive: isActive, isGreenTail: isGreenTail))
                            .overlay {
                                SlantedSegment(slant: slant)
                                    .stroke(Color.black.opacity(isActive ? 0.28 : 0.45), lineWidth: 1)
                            }
                            .shadow(
                                color: isActive ? segmentGlowColor(isGreenTail: isGreenTail) : .clear,
                                radius: compact ? 2 : 4
                            )
                            .frame(width: segmentWidth, height: height)
                    }
                }
                .offset(x: leadWidth)
            }
        }
        .frame(height: compact ? 14 : 22)
        .accessibilityLabel("Usage")
        .accessibilityValue("\(Int((clampedFraction * 100).rounded())) percent")
    }

    private func segmentColor(isActive: Bool, isGreenTail: Bool) -> Color {
        guard isActive else { return Color.secondary.opacity(0.16) }
        return isGreenTail ? Color.green.opacity(0.9) : Color.pink.opacity(0.95)
    }

    private func segmentGlowColor(isGreenTail: Bool) -> Color {
        isGreenTail ? Color.green.opacity(0.6) : Color.pink.opacity(0.5)
    }
}

private struct SlantedSegment: Shape {
    var slant: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = min(slant, rect.width * 0.6)
        var path = Path()
        path.move(to: CGPoint(x: dx, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - dx, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A sine-wave water surface at `progress` height (0 = empty, 1 = full),
/// closed off at the bottom so it fills like liquid. `phase` scrolls the wave
/// to animate it.
private struct WaterWave: Shape {
    var progress: CGFloat
    var waveHeight: CGFloat
    var phase: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, phase) }
        set {
            progress = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let level = rect.height * (1 - min(max(progress, 0), 1))
        path.move(to: CGPoint(x: 0, y: level))
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x <= rect.width {
            let relative = x / rect.width
            let y = level + sin(relative * 2 * .pi + phase) * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// A circular "tank" that fills with tinted water to show remaining quota.
/// Two offset waves give it a playful, layered ripple. The wave scrolls
/// continuously in the app; the widget renders it static (widgets can't
/// run repeating animations).
private struct WaterBallView: View {
    var remaining: CGFloat
    var tint: Color
    var animated: Bool

    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let amplitude = max(1.5, side * 0.045)
            ZStack {
                Circle().fill(Color.secondary.opacity(0.12))

                WaterWave(progress: remaining, waveHeight: amplitude, phase: phase + .pi)
                    .fill(tint.opacity(0.35))

                WaterWave(progress: remaining, waveHeight: amplitude, phase: phase)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.9), tint.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1)
            }
            .clipShape(Circle())
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
