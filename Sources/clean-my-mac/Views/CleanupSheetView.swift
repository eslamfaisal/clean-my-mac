import SwiftUI

struct CleanupSheetView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let plan = viewModel.cleanupPlan {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Cleanup")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Selected items will be moved to Trash. Review warnings before continuing.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TagPill(title: plan.estimatedReclaimedBytes.byteString, tint: AppPalette.accent)
                }
                .glassCard()

                if !plan.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Warnings")
                            .font(.headline)
                        ForEach(plan.warnings, id: \.self) { warning in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppPalette.warning)
                                Text(warning)
                            }
                        }
                    }
                    .glassCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Cleanup Plan")
                            .font(.headline)
                        Spacer()
                        Text("\(plan.items.count) items")
                            .foregroundStyle(.secondary)
                    }

                    Table(plan.items) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Updated") { item in
                            Text(item.updatedAt.map(AppFormatting.absoluteDate(_:)) ?? "Unknown")
                        }
                        TableColumn("Category") { item in
                            Text(item.category.title)
                        }
                        TableColumn("Size") { item in
                            Text(item.sizeDisplayString)
                                .fontWeight(.semibold)
                        }
                        TableColumn("Folder") { item in
                            Text(item.folderPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .glassCard()

                Spacer()

                HStack {
                    Button("Cancel") {
                        viewModel.dismissCleanupSheet()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Move to Trash") {
                        viewModel.executeCleanup()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("No cleanup plan prepared.")
                    .glassCard()
            }
        }
        .padding(24)
        .background(AppBackdrop())
    }
}
