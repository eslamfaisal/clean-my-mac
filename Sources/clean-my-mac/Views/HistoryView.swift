import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan History")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Track what was flagged and what has already been moved to Trash.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .glassCard()

                if viewModel.historyEntries.isEmpty {
                    Text("Run a scan to build your first history entry.")
                        .foregroundStyle(.secondary)
                        .glassCard()
                } else {
                    ForEach(viewModel.historyEntries) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(AppFormatting.absoluteDate(entry.scannedAt))
                                    .font(.headline)
                                Spacer()
                                TagPill(title: entry.cleanedBytes.byteString, tint: AppPalette.accent)
                            }

                            HStack(spacing: 18) {
                                stat("Flagged", entry.matchedBytes.byteString)
                                stat("Cleaned", entry.cleanedBytes.byteString)
                                stat("Items", "\(entry.itemCount)")
                            }

                            if !entry.categoryBreakdown.isEmpty {
                                Divider()
                                ForEach(entry.categoryBreakdown.keys.sorted(), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(entry.categoryBreakdown[key, default: 0].byteString)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .glassCard()
                    }
                }
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}
