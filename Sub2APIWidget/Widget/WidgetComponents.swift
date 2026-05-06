import SwiftUI
import WidgetKit

struct WidgetHeader: View {
    var title: String
    var systemImage: String
    var snapshot: MonitorSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(WidgetTheme.blue)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
            Spacer(minLength: 4)
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(WidgetTheme.orange)
                    .font(.caption)
            }
            Text(MetricFormatters.clockTime(snapshot.generatedAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(snapshot.isStale ? WidgetTheme.orange : WidgetTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

struct Badge: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .widgetSurface(tint: tint, opacity: 0.16, cornerRadius: 999)
    }
}

struct CompactWidgetHeader: View {
    var title: String
    var systemImage: String
    var snapshot: MonitorSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(WidgetTheme.blue)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetTheme.text)
                .lineLimit(1)
            Spacer(minLength: 3)
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(WidgetTheme.orange)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(MetricFormatters.clockTime(snapshot.generatedAt))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(snapshot.isStale ? WidgetTheme.orange : WidgetTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

struct StatusLine: View {
    var label: String
    var status: ServiceStatus

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(WidgetTheme.secondary)
            Spacer()
            Text(status.displayName)
                .foregroundStyle(statusColor(status))
                .fontWeight(.bold)
        }
        .font(.caption)
    }
}

struct EmptyState: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(WidgetTheme.secondary)
    }
}

func statusColor(_ status: ServiceStatus) -> Color {
    switch status {
    case .ok: WidgetTheme.green
    case .warning: WidgetTheme.orange
    case .error: WidgetTheme.red
    case .unknown: WidgetTheme.secondary
    }
}

extension View {
    func widgetPadding() -> some View {
        self.padding(16)
    }

    func compactWidgetPadding() -> some View {
        self.padding(14)
    }

    func widgetSurface(tint: Color = WidgetTheme.border, opacity: Double = 0.12, cornerRadius: CGFloat = 7) -> some View {
        modifier(WidgetSurfaceModifier(tint: tint, opacity: opacity, cornerRadius: cornerRadius))
    }
}

private struct WidgetSurfaceModifier: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground

    var tint: Color
    var opacity: Double
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if showsWidgetContainerBackground {
                    shape.fill(surfaceFill)
                }
            }
            .overlay {
                shape.stroke(surfaceStroke, lineWidth: renderingMode == .fullColor ? 0.7 : 1.0)
            }
    }

    private var surfaceFill: Color {
        if renderingMode == .fullColor {
            tint.opacity(opacity)
        } else {
            Color.primary.opacity(0.055)
        }
    }

    private var surfaceStroke: Color {
        if renderingMode == .fullColor {
            WidgetTheme.border
        } else {
            Color.primary.opacity(0.22)
        }
    }
}
