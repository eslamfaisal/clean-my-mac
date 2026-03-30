import SwiftUI

enum AppPalette {
    static let accent = Color(red: 0.24, green: 0.77, blue: 0.67)
    static let secondaryAccent = Color(red: 0.16, green: 0.51, blue: 0.95)
    static let surface = Color(red: 0.10, green: 0.12, blue: 0.17)
    static let surfaceRaised = Color(red: 0.14, green: 0.16, blue: 0.22)
    static let deepSurface = Color.black.opacity(0.42)
    static let warm = Color(red: 0.96, green: 0.71, blue: 0.38)
    static let warning = Color(red: 0.94, green: 0.45, blue: 0.33)
    static let outline = Color.white.opacity(0.08)
    static let tile = Color.white.opacity(0.04)
}

struct AppBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.06, green: 0.10, blue: 0.12),
                    Color(red: 0.09, green: 0.07, blue: 0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppPalette.secondaryAccent.opacity(0.22))
                .frame(width: 380)
                .offset(x: 360, y: -240)
                .blur(radius: 42)

            Circle()
                .fill(AppPalette.accent.opacity(0.18))
                .frame(width: 320)
                .offset(x: -360, y: 280)
                .blur(radius: 36)
        }
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.surfaceRaised.opacity(0.96), AppPalette.surface.opacity(0.94)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(AppPalette.outline, lineWidth: 1)
                    )
            )
            .shadow(color: AppPalette.deepSurface, radius: 24, y: 12)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

struct MetricBadge: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .padding(10)
                .background(Circle().fill(tint.opacity(0.15)))

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct TagPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }
}
