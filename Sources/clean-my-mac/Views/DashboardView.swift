import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 980

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero(compact: compact)

                    LazyVGrid(columns: metricColumns(for: proxy.size.width), spacing: 18) {
                        MetricBadge(
                            title: "Reclaimable Space",
                            value: viewModel.scanSnapshot?.totalMatchedBytes.byteString ?? "Pending",
                            symbol: "shippingbox.fill",
                            tint: AppPalette.accent
                        )
                        MetricBadge(
                            title: "Selected for Cleanup",
                            value: viewModel.selectedReclaimableBytes.byteString,
                            symbol: "checkmark.circle.fill",
                            tint: AppPalette.secondaryAccent
                        )
                        MetricBadge(
                            title: "Recommended Items",
                            value: "\(viewModel.recommendedItemCount)",
                            symbol: "sparkles",
                            tint: AppPalette.warm
                        )
                        MetricBadge(
                            title: "Categories Flagged",
                            value: "\(viewModel.categorySummaries.count)",
                            symbol: "square.grid.3x2.fill",
                            tint: AppPalette.warning
                        )
                    }

                    if viewModel.permissionSnapshot.requiresAttention {
                        permissionPanel(compact: compact)
                    }

                    categorySummaryPanel
                    topOffendersPanel
                }
                .frame(maxWidth: 1180, alignment: .leading)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func hero(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 18) {
                    heroSummary
                    flowPanel
                }
            } else {
                HStack(alignment: .top, spacing: 24) {
                    heroSummary
                    Spacer(minLength: 0)
                    flowPanel
                        .frame(width: 320)
                }
            }
        }
        .glassCard()
    }

    private func permissionPanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions")
                .font(.title2.weight(.bold))

            ForEach(viewModel.permissionSnapshot.statuses) { status in
                Group {
                    if compact {
                        VStack(alignment: .leading, spacing: 12) {
                            permissionHeader(for: status)
                            permissionBody(for: status)
                            if status.state != .granted {
                                Button("Open Settings") {
                                    viewModel.openSystemSettings(for: status.requirement)
                                }
                            }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: status.state == .granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(status.state == .granted ? AppPalette.accent : AppPalette.warning)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                permissionHeader(for: status)
                                permissionBody(for: status)
                            }

                            if status.state != .granted {
                                Button("Open Settings") {
                                    viewModel.openSystemSettings(for: status.requirement)
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppPalette.tile)
                )
            }
        }
        .glassCard()
    }

    private var categorySummaryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Category Browser")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Review All") {
                    viewModel.selectCategory(nil)
                }
            }

            if viewModel.categorySummaries.isEmpty {
                Text("Run a scan to populate category summaries and top offenders.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.categorySummaries, id: \.category.id) { summary in
                        Button {
                            viewModel.selectCategory(summary.category)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: summary.category.symbolName)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(AppPalette.secondaryAccent)
                                    Spacer()
                                    TagPill(title: summary.highestRisk.title, tint: tint(for: summary.highestRisk))
                                }

                                Text(summary.category.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(summary.category.rationale)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                Divider()

                                HStack {
                                    statItem("\(summary.itemCount) items")
                                    Spacer()
                                    statItem(summary.totalBytes.byteString)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .glassCard()
    }

    private var topOffendersPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Top Offenders")
                    .font(.title2.weight(.bold))
                Spacer()
                if let lastResult = viewModel.lastCleanupResult {
                    Text("Last cleanup: \(lastResult.reclaimedBytes.byteString)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.topOffenders.isEmpty {
                Text("No flagged items yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.topOffenders, id: \.id) { item in
                        HStack(spacing: 16) {
                            Image(systemName: item.category.symbolName)
                                .foregroundStyle(AppPalette.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(item.path)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(item.sizeDisplayString)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(item.category.title)
                                    .foregroundStyle(.secondary)
                            }

                            offenderMenu(for: item)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppPalette.tile)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.inspect(item)
                        }
                        .contextMenu {
                            offenderMenuItems(for: item)
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    private var heroSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            TagPill(title: "Review-first cleanup", tint: AppPalette.accent)

            Text("Grant access, scan the Mac, and review exactly what should move to Trash.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("The scanner prioritizes build artifacts, dependency caches, logs, installers, and large files. Nothing is deleted until you approve it.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(viewModel.isScanning ? "Cancel Scan" : "Scan Mac") {
                    viewModel.isScanning ? viewModel.cancelScan() : viewModel.presentScanSetup()
                }
                .buttonStyle(.borderedProminent)

                Button("Open Review Workspace") {
                    viewModel.selectedSection = .review
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var flowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flow")
                .font(.headline)
                .foregroundStyle(.secondary)
            flowRow(index: "01", title: "Grant Access", detail: "Guide the user to Full Disk Access when needed.")
            flowRow(index: "02", title: "Choose Scope", detail: "Pick quick scan, current user, full Mac, or a specific folder before scanning.")
            flowRow(index: "03", title: "Review", detail: "Inspect exact paths, sizes, rationale, and risk per item.")
            flowRow(index: "04", title: "Clean Selected", detail: "Move approved items to Trash with failure handling.")
        }
        .glassCard()
    }

    private func metricColumns(for width: CGFloat) -> [GridItem] {
        let minimumWidth: CGFloat = width < 980 ? 220 : 240
        return [GridItem(.adaptive(minimum: minimumWidth, maximum: 320), spacing: 18)]
    }

    private func permissionHeader(for status: PermissionStatus) -> some View {
        HStack {
            if status.state != .granted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppPalette.warning)
            }
            Text(status.requirement.title)
                .font(.headline)
            Spacer()
            TagPill(
                title: status.state.statusLabel,
                tint: status.state == .granted ? AppPalette.accent : AppPalette.warning
            )
        }
    }

    private func permissionBody(for status: PermissionStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(status.requirement.summary)
                .foregroundStyle(.secondary)

            Text(status.details)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func statItem(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func flowRow(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.secondaryAccent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tint(for risk: ScanRisk) -> Color {
        switch risk {
        case .low:
            return AppPalette.accent
        case .medium:
            return AppPalette.warm
        case .high:
            return AppPalette.warning
        }
    }

    private func offenderMenu(for item: ScanItem) -> some View {
        Menu {
            offenderMenuItems(for: item)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(AppPalette.tile.opacity(0.95))
                )
        }
        .menuStyle(.borderlessButton)
        .help("Item actions")
    }

    @ViewBuilder
    private func offenderMenuItems(for item: ScanItem) -> some View {
        Button("Inspect Details") {
            viewModel.inspect(item)
        }

        Button("Reveal in Finder") {
            viewModel.reveal(item)
        }

        Button("Open Folder") {
            viewModel.openFolder(for: item)
        }

        Button("Copy Path") {
            viewModel.copyPath(of: item)
        }

        Button("Exclude Folder") {
            viewModel.excludeItemFolder(item)
        }

        Button("Open Item") {
            viewModel.open(item)
        }

        Divider()

        Button("Move to Trash") {
            viewModel.presentCleanupSheet(for: item)
        }
    }
}
