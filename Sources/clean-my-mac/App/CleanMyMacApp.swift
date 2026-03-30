import SwiftUI

@main
struct CleanMyMacApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            AppShellView(viewModel: viewModel)
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Mac") {
                    viewModel.presentScanSetup()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Clean Selected Items") {
                    viewModel.presentCleanupSheet()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(viewModel.selectedItemIDs.isEmpty)
            }
        }
    }
}
