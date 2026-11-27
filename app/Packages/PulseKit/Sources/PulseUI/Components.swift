import Charts
import PulseCore
import SwiftUI

/// Rounded card used for every metric.
struct Tile<Content: View>: View {
    let icon: String
    let title: String
    var chip: String?
    var chipLevel: Level?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 12)
                Text(title).font(Theme.title).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                if let chip { Chip(text: chip, level: chipLevel).fixedSize() }
            }
            content
        }
        .padding(Theme.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tileFill, in: .rect(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let text: String
    var level: Level?

    var body: some View {
        Text(text)
            .font(Theme.chip)
            .foregroundStyle(level == nil || level == .good ? Color.primary.opacity(0.85) : Theme.color(level!))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(level == nil || level == .good ? Theme.chipFill : Theme.color(level!).opacity(0.16),
                        in: .rect(cornerRadius: 5))
    }
}

/// "24 %" — big rounded digits with a smaller unit.
struct BigValue: View {
    let number: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(number).font(Theme.bigNumber).contentTransition(.numericText())
            Text(unit).font(Theme.unit).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

struct Caption: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 0) {
            Text(text).lineLimit(1).layoutPriority(1)
            if let trailing {
                Spacer(minLength: 4)
                Text(trailing).lineLimit(1).fixedSize().foregroundStyle(.primary.opacity(0.9))
            }
        }
        .font(Theme.caption)
        .foregroundStyle(.secondary)
    }
}

/// One small bar per CPU thread, like Mole's per-core strip.
struct ThreadBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let n = max(values.count, 1)
            let spacing: CGFloat = 2.5
            let w = (geo.size.width - spacing * CGFloat(n - 1)) / CGFloat(n)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Theme.barColor(v))
                            .frame(width: w, height: max(2, geo.size.height * v / 100))
                    }
                }
            }
            .animation(.smooth(duration: 0.4), value: values)
        }
        .frame(height: Theme.chartHeight)
        .accessibilityHidden(true)
    }
}

/// Sparkline with an optional soft fill. Values are drawn on a fixed or
/// auto-scaled Y domain.
struct Sparkline: View {
    struct Series: Identifiable {
        let id: String
        let color: Color
        let values: [Double]
    }

    let series: [Series]
    var domain: ClosedRange<Double>?
    var filled = false

    var body: some View {
        let maxValue = series.flatMap(\.values).max() ?? 0
        let yDomain = domain ?? 0...max(maxValue * 1.25, 1)
        Chart {
            ForEach(series) { s in
                ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                    if filled {
                        AreaMark(x: .value("t", i), yStart: .value("v", yDomain.lowerBound), yEnd: .value("v", v))
                            .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.35), s.color.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", s.id))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
        .frame(height: Theme.chartHeight)
        .accessibilityHidden(true)
    }
}

struct Meter: View {
    let fraction: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(8, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 7)
        .padding(.vertical, (Theme.chartHeight - 7) / 2)
        .accessibilityHidden(true)
    }
}

/// Section card with a header row, used for containers and sites.
struct Section<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, Theme.tilePadding)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.tileFill, in: .rect(cornerRadius: Theme.tileRadius, style: .continuous))
        }
}

struct StatusDot: View {
    let level: Level
    var size: CGFloat = 6

    var body: some View {
        Circle().fill(Theme.color(level)).frame(width: size, height: size)
            .shadow(color: Theme.color(level).opacity(0.6), radius: level == .good ? 0 : 2)
    }
}
