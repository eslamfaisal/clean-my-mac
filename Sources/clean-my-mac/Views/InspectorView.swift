import SwiftUI

struct InspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let item = viewModel.selectedInspectorItem {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: item.category.symbolName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppPalette.secondaryAccent)
                        Spacer()
                        TagPill(title: item.recommendation.title, tint: item.recommendation == .recommended ? AppPalette.accent : AppPalette.warm)
                    }

                    Text(item.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(item.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Divider()

                    detailRow("Category", value: item.category.title)
                    detailRow("Folder", value: item.folderPath)
                    detailRow("Size", value: item.sizeDisplayString)
                    if item.sizing != .exact {
                        detailRow("Scan Mode", value: item.scanCaptureDescription)
                    }
                    detailRow("Risk", value: item.risk.title)
                    detailRow("Toolchain", value: item.toolchain ?? "General")
                    detailRow("Last Used", value: item.lastUsedDate.map(AppFormatting.absoluteDate(_:)) ?? "Unknown")
                    detailRow("Modified", value: item.modifiedDate.map(AppFormatting.absoluteDate(_:)) ?? "Unknown")

                    Divider()

                    Text("Why it was flagged")
                        .font(.headline)
                    Text(item.reason)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Reveal in Finder") {
                            viewModel.reveal(item)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open Folder") {
                            viewModel.openFolder(for: item)
                        }
                        .buttonStyle(.bordered)

                        Button("Open") {
                            viewModel.open(item)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        Button("Copy Path") {
                            viewModel.copyPath(of: item)
                        }
                        .buttonStyle(.bordered)

                        Button("Exclude Folder") {
                            viewModel.excludeItemFolder(item)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .glassCard()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Select a row in the review workspace to inspect metadata, rationale, and Finder actions.")
                        .foregroundStyle(.secondary)
                }
                .glassCard()
            }

            Spacer()
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
