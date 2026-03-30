import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    AppLogoMark(size: 68)
                    AppWordmark()
                }
                Text("Whole-disk scanning for developer junk, large files, build output, and stale clutter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .glassCard()

            List(selection: $viewModel.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.symbolName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TagPill(
                        title: viewModel.permissionSnapshot.requiresAttention ? "Setup Needed" : "Ready",
                        tint: viewModel.permissionSnapshot.requiresAttention ? AppPalette.warning : AppPalette.accent
                    )
                    Spacer()
                    if viewModel.isScanning {
                        TagPill(title: "Scanning", tint: AppPalette.secondaryAccent)
                    }
                }

                statRow("Selected", value: viewModel.selectedReclaimableBytes.byteString)
                statRow("Flagged", value: viewModel.scanSnapshot?.totalMatchedBytes.byteString ?? "Nothing yet")
                statRow("Rules", value: "\(viewModel.rules.count)")
            }
            .glassCard()
        }
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}
