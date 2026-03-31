import AppKit
import SwiftUI

struct AppShellView: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("layout.sidebarVisible") private var isSidebarVisible = true
    @AppStorage("layout.inspectorVisible") private var isInspectorVisible = true
    @AppStorage("layout.scanOverlayMinimized") private var isScanOverlayMinimized = false
    @State private var isPermissionAlertPresented = false

    var body: some View {
        ZStack {
            AppBackdrop()

            HSplitView {
                if isSidebarVisible {
                    SidebarView(viewModel: viewModel)
                        .padding(18)
                        .frame(minWidth: 250, idealWidth: 270, maxWidth: 300)
                }

                contentView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 18)
                    .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if isInspectorVisible {
                    InspectorView(viewModel: viewModel)
                        .padding(18)
                        .frame(minWidth: 290, idealWidth: 320, maxWidth: 360)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 10) {
                        AppLogoMark(size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("CleanMyMac")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("Disk cleanup studio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isSidebarVisible.toggle()
                    } label: {
                        ToolbarPanelToggleLabel(
                            title: "Menu",
                            symbolName: "sidebar.left",
                            isVisible: isSidebarVisible
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")

                    Button {
                        isInspectorVisible.toggle()
                    } label: {
                        ToolbarPanelToggleLabel(
                            title: "Inspector",
                            symbolName: "sidebar.right",
                            isVisible: isInspectorVisible
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isInspectorVisible ? "Hide inspector" : "Show inspector")
                }

                ToolbarItem(placement: .principal) {
                    if viewModel.isScanning {
                        ToolbarStatusView(viewModel: viewModel, showsDisclosure: false)
                            .frame(width: 290)
                    } else if viewModel.permissionSnapshot.requiresAttention {
                        Button {
                            isPermissionAlertPresented = true
                        } label: {
                            ToolbarStatusView(viewModel: viewModel, showsDisclosure: false)
                                .frame(width: 290)
                        }
                        .buttonStyle(.plain)
                        .help("Click to see permission details")
                    } else {
                        Menu {
                            Section("Start Scan") {
                                ForEach(ScanApproach.allCases) { approach in
                                    Button {
                                        viewModel.startScan(approach: approach)
                                    } label: {
                                        Label(approach.title, systemImage: approach.symbolName)
                                    }
                                }
                            }

                            Divider()

                            Button("Open Full Scan Setup") {
                                viewModel.presentScanSetup()
                            }
                        } label: {
                            ToolbarStatusView(viewModel: viewModel, showsDisclosure: true)
                                .frame(width: 290)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                        .help("Choose and start a scan from the header")
                    }
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button("Select Safe") {
                        viewModel.selectRecommendedItems()
                    }
                    .frame(width: 112)
                    .disabled(viewModel.totalItemCount == 0 || viewModel.isScanning)

                    Button(viewModel.isScanning ? "Cancel Scan" : "Scan Mac") {
                        viewModel.isScanning ? viewModel.cancelScan() : viewModel.presentScanSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(width: 116)

                    Button("Clean Selected") {
                        viewModel.presentCleanupSheet()
                    }
                    .buttonStyle(.bordered)
                    .frame(width: 122)
                    .disabled(!viewModel.canCleanSelection)
                }
            }

            if viewModel.isScanning {
                VStack {
                    Spacer()
                    Group {
                        if isScanOverlayMinimized {
                            MinimizedScanOverlay(viewModel: viewModel) {
                                isScanOverlayMinimized = false
                            }
                        } else {
                            ScanActivityOverlay(viewModel: viewModel) {
                                isScanOverlayMinimized = true
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(2)
            }

            if let presentation = viewModel.scanCompletionPresentation {
                VStack {
                    ScanCompletionBanner(presentation: presentation)
                        .padding(.top, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .zIndex(3)
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.84), value: viewModel.isScanning)
        .animation(.spring(response: 0.52, dampingFraction: 0.84), value: viewModel.scanCompletionPresentation != nil)
        .sheet(isPresented: $viewModel.isCleanupSheetPresented) {
            CleanupSheetView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 520)
        }
        .sheet(isPresented: $viewModel.isScanSetupPresented) {
            ScanSetupSheetView(viewModel: viewModel)
                .frame(minWidth: 880, minHeight: 720)
        }
        .onChange(of: viewModel.isScanning) { _, isScanning in
            if !isScanning {
                isScanOverlayMinimized = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissions()
        }
        .alert("Full Disk Access Required", isPresented: $isPermissionAlertPresented) {
            Button("Open System Settings") {
                viewModel.openSystemSettings(for: .fullDiskAccess)
            }
            .keyboardShortcut(.defaultAction)
            Button("Later", role: .cancel) {}
        } message: {
            Text("CleanMyMac needs Full Disk Access to inspect protected caches, logs, and developer artifacts.\n\nOpen System Settings → Privacy & Security → Full Disk Access and enable this app.")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.selectedSection {
        case .dashboard:
            DashboardView(viewModel: viewModel)
        case .review:
            ReviewWorkspaceView(viewModel: viewModel)
        case .exclusions:
            ExclusionsView(viewModel: viewModel)
        case .history:
            HistoryView(viewModel: viewModel)
        }
    }
}

private struct ToolbarPanelToggleLabel: View {
    let title: String
    let symbolName: String
    let isVisible: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isVisible ? Color.primary : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: title == "Inspector" ? 82 : 68)
        .background(
            Capsule(style: .continuous)
                .fill(isVisible ? AppPalette.tile.opacity(1.2) : AppPalette.tile.opacity(0.55))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isVisible ? AppPalette.secondaryAccent.opacity(0.22) : AppPalette.outline, lineWidth: 1)
                )
        )
    }
}

private struct ToolbarStatusView: View {
    @ObservedObject var viewModel: AppViewModel
    let showsDisclosure: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppPalette.tile)
                    .frame(width: 26, height: 26)

                if viewModel.isScanning {
                    ToolbarScannerGlyph(progress: viewModel.scanPhaseFraction)
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(symbolTint)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.toolbarHeadline)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(viewModel.toolbarDetail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(AppPalette.tile)

                if viewModel.isScanning {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppPalette.secondaryAccent.opacity(0.10),
                                    AppPalette.accent.opacity(0.08),
                                    AppPalette.secondaryAccent.opacity(0.04)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                Capsule(style: .continuous)
                    .strokeBorder(viewModel.isScanning ? AppPalette.secondaryAccent.opacity(0.18) : AppPalette.outline, lineWidth: 1)
            }
        )
    }

    private var symbolName: String {
        if viewModel.lastCleanupResult != nil {
            return "checkmark.circle.fill"
        }
        if viewModel.scanSnapshot != nil {
            return "sparkles"
        }
        return viewModel.permissionSnapshot.requiresAttention ? "lock.shield.fill" : "play.circle.fill"
    }

    private var symbolTint: Color {
        if viewModel.lastCleanupResult != nil {
            return AppPalette.accent
        }
        if viewModel.scanSnapshot != nil {
            return AppPalette.secondaryAccent
        }
        return viewModel.permissionSnapshot.requiresAttention ? AppPalette.warning : AppPalette.accent
    }
}
