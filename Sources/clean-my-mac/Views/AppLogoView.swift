import SwiftUI

struct AppLogoMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.20, green: 0.27, blue: 0.39),
                            Color(red: 0.07, green: 0.10, blue: 0.16),
                            Color.black.opacity(0.96),
                        ],
                        center: .init(x: 0.35, y: 0.28),
                        startRadius: size * 0.06,
                        endRadius: size * 0.66
                    )
                )

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppPalette.accent.opacity(0.95),
                            AppPalette.secondaryAccent.opacity(0.98),
                            Color(red: 0.47, green: 0.84, blue: 1.0),
                            AppPalette.accent.opacity(0.95),
                        ],
                        center: .center
                    ),
                    lineWidth: size * 0.08
                )

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .padding(size * 0.12)

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.56, height: size * 0.66)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: size * 0.015)
                )

            VStack(spacing: size * 0.055) {
                Circle()
                    .fill(AppPalette.secondaryAccent.opacity(0.88))
                    .frame(width: size * 0.075, height: size * 0.075)
                RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: size * 0.24, height: size * 0.06)
                RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: size * 0.18, height: size * 0.05)
            }
            .offset(y: -size * 0.03)

            SweepCheckShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.64, green: 0.97, blue: 0.86),
                            AppPalette.accent,
                            AppPalette.secondaryAccent,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.50, height: size * 0.36)
                .offset(x: size * 0.02, y: size * 0.17)
                .shadow(color: AppPalette.accent.opacity(0.25), radius: size * 0.09, y: size * 0.03)

            SparkleShape()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color(red: 0.56, green: 0.90, blue: 1.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.17, height: size * 0.17)
                .offset(x: size * 0.21, y: -size * 0.22)

            SparkleShape()
                .fill(Color.white.opacity(0.85))
                .frame(width: size * 0.09, height: size * 0.09)
                .offset(x: -size * 0.22, y: -size * 0.12)
        }
        .frame(width: size, height: size)
        .shadow(color: AppPalette.secondaryAccent.opacity(0.16), radius: size * 0.16, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

struct AppWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CleanMyMac")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Developer Disk Cleanup Studio")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(AppPalette.secondaryAccent.opacity(0.9))
        }
    }
}

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        let top = CGPoint(x: midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: midY)
        let bottom = CGPoint(x: midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: midY)

        path.move(to: top)
        path.addQuadCurve(to: right, control: CGPoint(x: rect.maxX * 0.78, y: rect.minY + rect.height * 0.22))
        path.addQuadCurve(to: bottom, control: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY * 0.78))
        path.addQuadCurve(to: left, control: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.22))
        path.addQuadCurve(to: top, control: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.22))
        return path
    }
}

private struct SweepCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.midY + rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY - rect.height * 0.10))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.08),
            control1: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.20),
            control2: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.22)
        )
        return path
    }
}
