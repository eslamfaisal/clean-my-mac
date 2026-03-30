import AppKit
import SwiftUI

struct ReviewWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel

    private let keepColumnWidth: CGFloat = 56
    private let nameColumnWidth: CGFloat = 230
    private let categoryColumnWidth: CGFloat = 142
    private let recommendationColumnWidth: CGFloat = 146
    private let updatedColumnWidth: CGFloat = 168
    private let sizeColumnWidth: CGFloat = 110
    private let folderColumnWidth: CGFloat = 420
    private let actionColumnWidth: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 920

            VStack(alignment: .leading, spacing: 18) {
                header(compact: compact)
                filterBar
                itemTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 14) {
                    headerCopy
                    headerStats(alignment: .leading)
                }
            } else {
                HStack(alignment: .bottom) {
                    headerCopy
                    Spacer()
                    headerStats(alignment: .trailing)
                }
            }
        }
        .glassCard()
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Search paths or file names", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                Button(viewModel.allVisibleItemsSelected ? "Deselect Visible" : "Select Visible") {
                    viewModel.setVisibleItemsSelected(!viewModel.allVisibleItemsSelected)
                }
                Button("Clear") {
                    viewModel.searchText = ""
                    viewModel.selectCategory(nil)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    categoryChip(title: "All", category: nil, tint: AppPalette.secondaryAccent)
                    ForEach(viewModel.categorySummaries, id: \.category.id) { summary in
                        categoryChip(title: summary.category.title, category: summary.category, tint: AppPalette.accent)
                    }
                }
            }
        }
        .glassCard()
    }

    private var itemTable: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No scan results for the current filter.")
                        .font(.title3.weight(.semibold))
                    Text("Run a scan or adjust your category and search filters.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassCard()
            } else {
                VStack(spacing: 0) {
                    tableHeader

                    Divider()
                        .overlay(AppPalette.outline)

                    LegacyBidirectionalScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.visibleItems) { item in
                                reviewRow(item)
                            }
                        }
                        .frame(minWidth: tableWidth, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppPalette.tile.opacity(0.2))
                }
                .frame(minHeight: 420, maxHeight: .infinity)
                .padding(18)
                .background(tableCardBackground)
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review Workspace")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Inspect why each file was flagged, keep what you trust, and send only approved items to Trash.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Use the checkbox column to select multiple items, or the Trash button to delete a single item.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func headerStats(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(viewModel.selectedReclaimableBytes.byteString)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("selected across \(viewModel.selectedItemIDs.count) items")
                .foregroundStyle(.secondary)
        }
    }

    private func categoryChip(title: String, category: ScanCategory?, tint: Color) -> some View {
        Button {
            viewModel.selectCategory(category)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(viewModel.selectedCategory == category ? tint.opacity(0.24) : Color.white.opacity(0.36))
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var tableWidth: CGFloat {
        keepColumnWidth
            + nameColumnWidth
            + categoryColumnWidth
            + recommendationColumnWidth
            + updatedColumnWidth
            + sizeColumnWidth
            + folderColumnWidth
            + actionColumnWidth
            + 28
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            selectionHeaderCell
            headerCell("Name", width: nameColumnWidth, alignment: .leading)
            headerCell("Category", width: categoryColumnWidth, alignment: .leading)
            headerCell("Recommendation", width: recommendationColumnWidth, alignment: .leading)
            headerCell("Updated", width: updatedColumnWidth, alignment: .leading)
            headerCell("Size", width: sizeColumnWidth, alignment: .trailing)
            headerCell("Folder", width: folderColumnWidth, alignment: .leading)
            headerCell("Trash", width: actionColumnWidth, alignment: .center)
        }
        .frame(minWidth: tableWidth, alignment: .leading)
    }

    private var selectionHeaderCell: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { viewModel.allVisibleItemsSelected },
                set: { isSelected in
                    viewModel.setVisibleItemsSelected(isSelected)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text("Keep")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(width: keepColumnWidth, alignment: .leading)
        .help(viewModel.allVisibleItemsSelected ? "Deselect all visible items" : "Select all visible items")
    }

    private func reviewRow(_ item: ScanItem) -> some View {
        let isFocused = viewModel.focusedItemIDs.contains(item.id)

        return HStack(spacing: 0) {
            cell(width: keepColumnWidth, alignment: .leading) {
                Toggle("", isOn: Binding(
                    get: { viewModel.selectedItemIDs.contains(item.id) },
                    set: { isSelected in
                        viewModel.setSelection(isSelected, for: item.id)
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            cell(width: nameColumnWidth, alignment: .leading) {
                FileNameCell(item: item)
            }

            cell(width: categoryColumnWidth, alignment: .leading) {
                TagPill(title: item.category.title, tint: AppPalette.secondaryAccent)
            }

            cell(width: recommendationColumnWidth, alignment: .leading) {
                TagPill(
                    title: item.recommendation.title,
                    tint: item.recommendation == .recommended ? AppPalette.accent : AppPalette.warm
                )
            }

            cell(width: updatedColumnWidth, alignment: .leading) {
                Text(item.updatedAt.map(AppFormatting.absoluteDate(_:)) ?? "Unknown")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .monospacedDigit()
            }

            cell(width: sizeColumnWidth, alignment: .trailing) {
                Text(item.byteSize.byteString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            cell(width: folderColumnWidth, alignment: .leading) {
                Text(item.folderPath)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            cell(width: actionColumnWidth, alignment: .center) {
                Button {
                    viewModel.presentCleanupSheet(for: item)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(AppPalette.warning.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .help("Move this item to Trash")
            }
        }
        .frame(minWidth: tableWidth, alignment: .leading)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? AppPalette.secondaryAccent.opacity(0.12) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppPalette.outline)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.focusItemIDs([item.id])
        }
        .contextMenu {
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

            Divider()

            Button("Move to Trash") {
                viewModel.presentCleanupSheet(for: item)
            }
        }
    }

    private func headerCell(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(width: width, alignment: alignment)
    }

    private func cell<Content: View>(
        width: CGFloat,
        alignment: Alignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 10)
            .frame(width: width, alignment: alignment)
    }

    private var tableCardBackground: some View {
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
            .shadow(color: AppPalette.deepSurface, radius: 24, y: 12)
    }
}

private struct FileNameCell: View {
    let item: ScanItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .file ? "doc.fill" : "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.kind == .file ? AppPalette.secondaryAccent : AppPalette.warm)
                .frame(width: 16)

            Text(item.name)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private struct LegacyBidirectionalScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rootView: content)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .automatic
        scrollView.documentView = context.coordinator.hostingView

        context.coordinator.updateLayout(in: scrollView, rootView: content)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.updateLayout(in: scrollView, rootView: content)
    }

    @MainActor
    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(rootView: Content) {
            hostingView = NSHostingView(rootView: rootView)
        }

        func updateLayout(in scrollView: NSScrollView, rootView: Content) {
            hostingView.rootView = rootView
            hostingView.layoutSubtreeIfNeeded()

            let fittingSize = hostingView.fittingSize
            let contentSize = scrollView.contentSize
            let frameSize = CGSize(
                width: max(fittingSize.width, contentSize.width),
                height: max(fittingSize.height, contentSize.height)
            )

            hostingView.frame = CGRect(origin: .zero, size: frameSize)
        }
    }
}
