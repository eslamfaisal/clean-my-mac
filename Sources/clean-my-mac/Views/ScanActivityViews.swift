import SwiftUI

struct ScanActivityOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var shimmerPhase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !viewModel.isScanning)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 20) {
                ScanRadarOrb(time: time, progress: viewModel.scanPhaseFraction)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TagPill(title: viewModel.activeScanApproach.title, tint: AppPalette.secondaryAccent)
                        TagPill(title: viewModel.scanProgress?.phase.rawValue.capitalized ?? "Preparing", tint: AppPalette.accent)
                        Spacer()
                        cancelButton
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.scanPhaseTitle)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(viewModel.scanPhaseDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    ScanPhaseTrack(
                        progress: viewModel.scanPhaseFraction,
                        phase: viewModel.scanProgress?.phase ?? .preparing
                    )

                    HStack(spacing: 10) {
                        ScanMetricCapsule(title: "Visited", value: viewModel.scanProgress?.processedEntries.formatted() ?? "0")
                        ScanMetricCapsule(title: "Flagged", value: viewModel.scanProgress?.matchedItems.formatted() ?? "0")
                        ScanMetricCapsule(title: "Scope", value: viewModel.activeScanApproach.shortLabel)
                    }

                    if let currentPath = viewModel.scanProgress?.currentPath, !currentPath.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(AppPalette.warm)
                            Text(currentPath)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 920, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppPalette.surfaceRaised.opacity(0.98),
                                AppPalette.surface.opacity(0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                AngularGradient(
                                    colors: [
                                        AppPalette.secondaryAccent.opacity(0.30),
                                        AppPalette.accent.opacity(0.12),
                                        AppPalette.secondaryAccent.opacity(0.06),
                                        AppPalette.accent.opacity(0.30),
                                        AppPalette.secondaryAccent.opacity(0.12),
                                    ],
                                    center: .center,
                                    angle: .degrees(shimmerPhase)
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: AppPalette.deepSurface.opacity(0.8), radius: 30, y: 16)
            .overlay(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppPalette.secondaryAccent.opacity(0.14),
                                AppPalette.accent.opacity(0.06),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 54)
                    .blur(radius: 8)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan progress overlay")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 360
            }
        }
    }

    private var cancelButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                viewModel.cancelScan()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Cancel Scan")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppPalette.warning)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(AppPalette.warning.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(AppPalette.warning.opacity(0.28), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Cancel the active scan")
    }
}

struct ScanCompletionBanner: View {
    let presentation: ScanCompletionPresentation

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppPalette.accent.opacity(0.18))
                    .frame(width: 54, height: 54)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppPalette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Scan Complete")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("\(presentation.itemCount.formatted()) findings · \(presentation.totalBytes.byteString) · \(presentation.categoryCount.formatted()) categories")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            TagPill(title: presentation.approach.title, tint: AppPalette.secondaryAccent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: 680)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppPalette.surfaceRaised.opacity(0.98), AppPalette.surface.opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AppPalette.accent.opacity(0.24), lineWidth: 1)
                )
        )
        .shadow(color: AppPalette.deepSurface.opacity(0.75), radius: 24, y: 12)
    }
}

struct ToolbarScannerGlyph: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            ZStack {
                Circle()
                    .stroke(AppPalette.secondaryAccent.opacity(0.18), lineWidth: 1)
                    .frame(width: 22, height: 22)

                Circle()
                    .trim(from: 0.0, to: max(0.16, progress))
                    .stroke(
                        AngularGradient(
                            colors: [AppPalette.secondaryAccent, AppPalette.accent, AppPalette.secondaryAccent.opacity(0.2)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees((time * 120).truncatingRemainder(dividingBy: 360)))

                Circle()
                    .fill(AppPalette.accent.opacity(0.18))
                    .frame(width: 8 + CGFloat(sin(time * 3) * 1.2), height: 8 + CGFloat(sin(time * 3) * 1.2))

                Circle()
                    .fill(AppPalette.accent)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

private struct ScanMetricCapsule: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 110, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.tile.opacity(0.9))
        )
    }
}

private struct ScanPhaseTrack: View {
    let progress: Double
    let phase: ScanPhase

    private let steps: [(ScanPhase, String)] = [
        (.preparing, "Prepare"),
        (.inventory, "Inventory"),
        (.detection, "Classify"),
        (.aggregation, "Assemble"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppPalette.tile.opacity(0.9))
                    .frame(height: 10)

                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppPalette.secondaryAccent, AppPalette.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(18, proxy.size.width * progress), height: 10)
                }
            }
            .frame(height: 10)

            HStack(spacing: 12) {
                ForEach(steps, id: \.0.rawValue) { step in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isStepActive(step.0) ? AppPalette.accent : AppPalette.tile.opacity(0.9))
                            .frame(width: 8, height: 8)
                        Text(step.1)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(isStepActive(step.0) ? .primary : .secondary)
                    }
                }
            }
        }
    }

    private func isStepActive(_ step: ScanPhase) -> Bool {
        switch (step, phase) {
        case (.preparing, _):
            return true
        case (.inventory, .inventory), (.inventory, .detection), (.inventory, .aggregation), (.inventory, .completed):
            return true
        case (.detection, .detection), (.detection, .aggregation), (.detection, .completed):
            return true
        case (.aggregation, .aggregation), (.aggregation, .completed):
            return true
        default:
            return false
        }
    }
}

private struct ScanRadarOrb: View {
    let time: TimeInterval
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppPalette.secondaryAccent.opacity(0.18),
                            AppPalette.surfaceRaised,
                            AppPalette.surface
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 74
                    )
                )

            Circle()
                .stroke(AppPalette.secondaryAccent.opacity(0.22), lineWidth: 1)
                .padding(8)

            Circle()
                .stroke(AppPalette.accent.opacity(0.16), lineWidth: 1)
                .padding(20)

            Circle()
                .trim(from: 0, to: 0.28 + progress * 0.42)
                .stroke(
                    LinearGradient(
                        colors: [AppPalette.accent, AppPalette.secondaryAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees((time * 110).truncatingRemainder(dividingBy: 360)))
                .padding(10)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppPalette.secondaryAccent.opacity(0.0), AppPalette.secondaryAccent, AppPalette.accent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 10, height: 108)
                .blur(radius: 1.8)
                .rotationEffect(.degrees((time * 140).truncatingRemainder(dividingBy: 360)))

            Circle()
                .stroke(AppPalette.accent.opacity(0.20 - CGFloat((sin(time * 2) + 1) * 0.04)), lineWidth: 8)
                .scaleEffect(1.0 + CGFloat((sin(time * 2.4) + 1) * 0.08))
                .blur(radius: 0.5)
                .padding(4)

            VStack(spacing: 4) {
                Image(systemName: "scope")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.accent)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 148, height: 148)
    }
}

struct ScanPulsingDot: View {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(AppPalette.accent.opacity(0.20))
                    .frame(width: 18, height: 18)
                    .scaleEffect(isPulsing ? 1.6 : 0.9)
                    .opacity(isPulsing ? 0 : 0.6)
            }

            Circle()
                .fill(AppPalette.accent)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}
