import Foundation

protocol CleanupCoordinating: Sendable {
    func makePlan(items: [ScanItem], selectedIDs: Set<String>, rules: [UserRule]) -> CleanupPlan
    func execute(plan: CleanupPlan) -> CleanupResult
}

struct CleanupCoordinator: CleanupCoordinating {
    func makePlan(items: [ScanItem], selectedIDs: Set<String>, rules: [UserRule]) -> CleanupPlan {
        let selectedItems = items.filter { selectedIDs.contains($0.id) }
        let warnings = warningMessages(for: selectedItems)
        let excludedPaths = rules
            .filter { $0.kind == .excludedPath }
            .map(\.value)

        return CleanupPlan(
            items: selectedItems.sorted { $0.byteSize > $1.byteSize },
            estimatedReclaimedBytes: selectedItems.reduce(into: Int64.zero) { $0 += $1.byteSize },
            deleteMode: .moveToTrash,
            warnings: warnings,
            excludedPathsSnapshot: excludedPaths
        )
    }

    func execute(plan: CleanupPlan) -> CleanupResult {
        let fileManager = FileManager.default
        var succeededPaths: [String] = []
        var failedItems: [CleanupFailure] = []
        var reclaimedBytes: Int64 = 0
        var skippedBytes: Int64 = 0

        for item in plan.items {
            do {
                _ = try fileManager.trashItem(at: item.url, resultingItemURL: nil)
                succeededPaths.append(item.path)
                reclaimedBytes += item.byteSize
            } catch {
                failedItems.append(CleanupFailure(path: item.path, reason: error.localizedDescription))
                skippedBytes += item.byteSize
            }
        }

        return CleanupResult(
            succeededPaths: succeededPaths,
            failedItems: failedItems,
            reclaimedBytes: reclaimedBytes,
            skippedBytes: skippedBytes
        )
    }

    private func warningMessages(for items: [ScanItem]) -> [String] {
        guard !items.isEmpty else { return [] }

        var warnings: [String] = []
        if items.contains(where: { $0.risk == .high }) {
            warnings.append("Some selected items are high risk and may still be in active use. Review them carefully before cleaning.")
        }
        if items.contains(where: { $0.category == .applicationBuilds }) {
            warnings.append("Application build artifacts may still be needed for release distribution, QA installs, or rollback.")
        }
        if items.contains(where: { $0.category == .downloadsInstallers }) {
            warnings.append("Downloaded installer archives may be useful for rollback or offline reinstallation.")
        }
        if items.contains(where: { $0.category == .largeFiles }) {
            warnings.append("Large files are surfaced for review. Verify ownership before sending them to Trash.")
        }
        if items.contains(where: { $0.sizing == .estimatedFastFolder }) {
            warnings.append("Some generated folders use an estimated size because the scanner skipped deep descendant traversal for performance.")
        }
        return warnings
    }
}
