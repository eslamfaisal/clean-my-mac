import SwiftUI

struct ScanSetupSheetView: View {
    @ObservedObject var viewModel: AppViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(ScanApproach.allCases) { approach in
                            approachCard(approach)
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        scopePanel
                        categoryPanel
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    Rectangle()
                        .fill(AppPalette.surface.opacity(0.98))
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(AppPalette.outline)
                                .frame(height: 1)
                        }
                )
        }
        .background(AppBackdrop())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose Scan Approach")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Pick the scope before scanning. Each mode keeps the same classification engine, but changes how much of the Mac is traversed.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                TagPill(title: viewModel.selectedScanApproach.speedLabel, tint: AppPalette.secondaryAccent)
                TagPill(title: viewModel.selectedScanApproach.coverageLabel, tint: AppPalette.accent)
            }
        }
        .glassCard()
    }

    private func approachCard(_ approach: ScanApproach) -> some View {
        Button {
            viewModel.selectedScanApproach = approach
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: approach.symbolName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(viewModel.selectedScanApproach == approach ? AppPalette.accent : AppPalette.secondaryAccent)
                    Spacer()
                    if viewModel.selectedScanApproach == approach {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppPalette.accent)
                    }
                }

                Text(approach.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(approach.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                Text(approach.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(viewModel.selectedScanApproach == approach ? AppPalette.tile.opacity(1.4) : AppPalette.tile)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(viewModel.selectedScanApproach == approach ? AppPalette.secondaryAccent.opacity(0.45) : AppPalette.outline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var scopePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Scope")
                    .font(.title2.weight(.bold))
                Spacer()
                if viewModel.selectedScanApproach == .specificPath {
                    Button("Choose Folder") {
                        viewModel.chooseCustomScanFolder()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.selectedScanApproach == .specificPath {
                Text(viewModel.customScanPath.isEmpty ? "No folder selected yet." : viewModel.customScanPath)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(viewModel.customScanPath.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppPalette.tile)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.scanApproachPreviewPaths, id: \.self) { path in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(AppPalette.warm)
                        Text(path)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What Will Be Classified")
                .font(.title2.weight(.bold))

            Text("The scan will classify files and folders into the enabled cleanup categories below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(viewModel.enabledScanCategories) { category in
                    HStack(spacing: 10) {
                        Image(systemName: category.symbolName)
                            .foregroundStyle(AppPalette.secondaryAccent)
                        Text(category.title)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppPalette.tile)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Permission note")
                    .font(.headline)
                Text("Full Mac scans work best with Full Disk Access enabled. Without it, the app still scans accessible areas and reports what it can classify.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") {
                viewModel.dismissScanSetup()
            }
            .buttonStyle(.bordered)

            Button("Start \(viewModel.selectedScanApproach.title)") {
                viewModel.startConfiguredScan()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStartSelectedScan)
        }
        .glassCard()
    }
}
