import Foundation
import SwiftUI
import AppKit

struct ScanCompletionPresentation: Identifiable, Equatable {
    let id = UUID()
    let approach: ScanApproach
    let itemCount: Int
    let totalBytes: Int64
    let categoryCount: Int
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case review
    case exclusions
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .review:
            return "Review"
        case .exclusions:
            return "Exclusions"
        case .history:
            return "History"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2.fill"
        case .review:
            return "checklist.checked"
        case .exclusions:
            return "line.3.horizontal.decrease.circle.fill"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    private enum CleanupSheetSource {
        case bulk
        case singleItem(selectionSnapshot: Set<String>, focusSnapshot: Set<String>)
    }

    private struct PreScanState {
        let selectedSection: AppSection
        let selectedCategory: ScanCategory?
        let items: [ScanItem]
        let scanSnapshot: ScanSnapshot?
        let selectedItemIDs: Set<String>
        let focusedItemIDs: Set<String>
        let lastCleanupResult: CleanupResult?
    }

    @Published var selectedSection: AppSection = .dashboard
    @Published var permissionSnapshot: PermissionSnapshot
    @Published var scanSnapshot: ScanSnapshot?
    @Published var items: [ScanItem] = []
    @Published var scanProgress: ScanProgress?
    @Published var isScanning = false
    @Published var searchText = ""
    @Published var selectedScanApproach: ScanApproach = .quick
    @Published var customScanPath = ""
    @Published var activeScanApproach: ScanApproach = .quick
    @Published var selectedCategory: ScanCategory?
    @Published var selectedItemIDs: Set<String> = []
    @Published var focusedItemIDs: Set<String> = []
    @Published var rules: [UserRule] = []
    @Published var historyEntries: [ScanHistoryEntry] = []
    @Published var cleanupPlan: CleanupPlan?
    @Published var isCleanupSheetPresented = false
    @Published var isScanSetupPresented = false
    @Published var lastCleanupResult: CleanupResult?
    @Published var scanCompletionPresentation: ScanCompletionPresentation?
    @Published var statusMessage = "Ready to inspect your Mac."

    private let permissionCenter: PermissionProviding
    private let scanner: ScanStreaming
    private let cleanupCoordinator: any CleanupCoordinating
    private let historyStore: HistoryStore
    private let finderBridge: FinderBridge
    private var scanTask: Task<Void, Never>?
    private var activeScanSessionID = UUID()
    private var preScanState: PreScanState?
    private var cleanupSheetSource: CleanupSheetSource?
    private var pendingScanItems: [ScanItem] = []
    private let scanPublishBatchSize = 160
    private let scanPublishInterval: TimeInterval = 0.18
    private let progressPublishInterval: TimeInterval = 0.12
    private var lastScanItemsFlushAt: TimeInterval = 0
    private var lastPublishedProgressAt: TimeInterval = 0
    private var lastPublishedProgressPhase: ScanPhase?
    private var completionPresentationTask: Task<Void, Never>?

    init(
        permissionCenter: PermissionProviding = PermissionCenter(),
        scanner: ScanStreaming = FileSystemScanner(),
        cleanupCoordinator: any CleanupCoordinating = CleanupCoordinator(),
        historyStore: HistoryStore = HistoryStore(),
        finderBridge: FinderBridge = FinderBridge()
    ) {
        self.permissionCenter = permissionCenter
        self.scanner = scanner
        self.cleanupCoordinator = cleanupCoordinator
        self.historyStore = historyStore
        self.finderBridge = finderBridge
        self.permissionSnapshot = permissionCenter.snapshot()

        Task { [weak self] in
            await self?.loadPersistedState()
        }
    }

    deinit {
        scanTask?.cancel()
    }

    var visibleItems: [ScanItem] {
        items.filter { item in
            let categoryMatch = selectedCategory.map { item.category == $0 } ?? true
            let queryMatch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText) || item.path.localizedCaseInsensitiveContains(searchText)
            return categoryMatch && queryMatch
        }
    }

    var selectedInspectorItem: ScanItem? {
        if let focusedID = focusedItemIDs.first {
            return items.first(where: { $0.id == focusedID })
        }
        if let selectedID = selectedItemIDs.first {
            return items.first(where: { $0.id == selectedID })
        }
        return nil
    }

    var categorySummaries: [CategorySummary] {
        scanSnapshot?.summaries ?? items.summaries()
    }

    var topOffenders: [ScanItem] {
        Array(items.prefix(8))
    }

    var selectedReclaimableBytes: Int64 {
        items.filter { selectedItemIDs.contains($0.id) }.reduce(into: Int64.zero) { $0 += $1.byteSize }
    }

    var allVisibleItemsSelected: Bool {
        let visibleIDs = Set(visibleItems.map(\.id))
        guard !visibleIDs.isEmpty else { return false }
        return visibleIDs.isSubset(of: selectedItemIDs)
    }

    var recommendedItemCount: Int {
        items.filter { $0.recommendation == .recommended }.count
    }

    var canCleanSelection: Bool {
        !selectedItemIDs.isEmpty && !isScanning
    }

    var toolbarHeadline: String {
        if isScanning {
            return "\(activeScanApproach.title)"
        }
        if lastCleanupResult != nil {
            return "Cleanup Finished"
        }
        if scanSnapshot != nil {
            return "Scan Complete"
        }
        return permissionSnapshot.requiresAttention ? "Access Needed" : "Ready"
    }

    var toolbarDetail: String {
        if isScanning, let progress = scanProgress {
            let visited = progress.processedEntries.formatted()
            let flagged = progress.matchedItems.formatted()
            return "\(activeScanApproach.shortLabel) · \(visited) visited · \(flagged) flagged"
        }
        if let result = lastCleanupResult {
            return "\(result.reclaimedBytes.byteString) moved to Trash"
        }
        if let snapshot = scanSnapshot {
            return "\(snapshot.items.count.formatted()) items · \(snapshot.totalMatchedBytes.byteString)"
        }
        return permissionSnapshot.requiresAttention ? "Grant Full Disk Access to scan protected folders" : "Run a full-disk cleanup scan"
    }

    var scanPhaseTitle: String {
        guard let progress = scanProgress else {
            return scanSnapshot == nil ? "Standby" : "Results ready"
        }

        switch progress.phase {
        case .preparing:
            return "Preparing scan"
        case .inventory:
            return "Mapping accessible folders"
        case .detection:
            return progress.currentCategory.map { "Classifying \($0.title)" } ?? "Scanning project data"
        case .aggregation:
            return "Grouping results"
        case .completed:
            return "Results assembled"
        }
    }

    var scanPhaseDetail: String {
        guard let progress = scanProgress else {
            if let snapshot = scanSnapshot {
                return "\(snapshot.items.count.formatted()) findings across \(categorySummaries.count.formatted()) categories"
            }
            return "Pick a scope and start scanning."
        }

        let visited = progress.processedEntries.formatted()
        let flagged = progress.matchedItems.formatted()

        switch progress.phase {
        case .preparing:
            return "Loading scan rules and preparing the workspace."
        case .inventory:
            return "Inventorying visible locations across the chosen scope."
        case .detection:
            if let currentPath = progress.currentPath, currentPath.isEmpty == false {
                return "\(visited) entries visited · \(flagged) findings · \(currentPath)"
            }
            return "\(visited) entries visited · \(flagged) findings"
        case .aggregation:
            return "Consolidating matched folders, categories, and totals."
        case .completed:
            return "Final summaries are ready."
        }
    }

    var scanPhaseFraction: Double {
        guard let phase = scanProgress?.phase else { return scanSnapshot == nil ? 0 : 1 }

        switch phase {
        case .preparing:
            return 0.10
        case .inventory:
            return 0.28
        case .detection:
            return 0.66
        case .aggregation:
            return 0.92
        case .completed:
            return 1.0
        }
    }

    func refreshPermissions() {
        permissionSnapshot = permissionCenter.snapshot()
    }

    func openSystemSettings(for requirement: PermissionRequirement) {
        permissionCenter.openSystemSettings(for: requirement)
    }

    var canStartSelectedScan: Bool {
        selectedScanApproach != .specificPath || !customScanPath.isEmpty
    }

    var scanApproachPreviewPaths: [String] {
        selectedScanApproach.previewPaths(customPath: customScanPath)
    }

    var enabledScanCategories: [ScanCategory] {
        ScanCategory.allCases.filter(isCategoryEnabled)
    }

    func presentScanSetup() {
        isScanSetupPresented = true
    }

    func dismissScanSetup() {
        isScanSetupPresented = false
    }

    @discardableResult
    func chooseCustomScanFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Select the folder you want to scan."

        if panel.runModal() == .OK, let url = panel.url {
            customScanPath = url.path
            return customScanPath
        }

        return nil
    }

    func startConfiguredScan() {
        guard let target = selectedScanApproach.buildTarget(customPath: customScanPath) else {
            statusMessage = "Choose a folder before starting a specific-folder scan."
            return
        }
        isScanSetupPresented = false
        startScan(target: target, approach: selectedScanApproach)
    }

    func startScan() {
        startScan(target: .internalVolume, approach: .fullMac)
    }

    func startScan(approach: ScanApproach) {
        selectedScanApproach = approach
        isScanSetupPresented = false

        if approach == .specificPath {
            guard let chosenPath = chooseCustomScanFolder(), !chosenPath.isEmpty else {
                statusMessage = "Specific-folder scan cancelled."
                return
            }
            customScanPath = chosenPath
        }

        guard let target = approach.buildTarget(customPath: customScanPath) else {
            statusMessage = "Unable to start \(approach.title.lowercased())."
            return
        }

        startScan(target: target, approach: approach)
    }

    private func startScan(target: ScanTarget, approach: ScanApproach) {
        let stableState = isScanning ? preScanState : captureCurrentState()
        completionPresentationTask?.cancel()
        completionPresentationTask = nil
        scanCompletionPresentation = nil
        scanTask?.cancel()
        scanTask = nil
        preScanState = stableState
        pendingScanItems.removeAll(keepingCapacity: true)
        lastScanItemsFlushAt = currentUptime
        lastPublishedProgressAt = 0
        lastPublishedProgressPhase = .preparing
        let sessionID = UUID()
        activeScanSessionID = sessionID
        refreshPermissions()
        activeScanApproach = approach
        isScanning = true
        statusMessage = permissionSnapshot.requiresAttention
            ? "Scanning accessible areas while permission setup is pending."
            : "Scanning your Mac for clutter and developer artifacts."
        selectedSection = .dashboard
        selectedCategory = nil
        focusedItemIDs.removeAll()
        selectedItemIDs.removeAll()
        scanProgress = ScanProgress(
            phase: .preparing,
            processedEntries: 0,
            matchedItems: 0,
            currentPath: nil,
            currentCategory: nil
        )
        items.removeAll()
        scanSnapshot = nil
        lastCleanupResult = nil

        let stream = scanner.scan(target: target, rules: rules)
        scanTask = Task { [weak self, sessionID] in
            guard let self else { return }
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    guard self.activeScanSessionID == sessionID else {
                        throw CancellationError()
                    }
                    self.handle(event)
                }
            } catch is CancellationError {
                self.finishCancelledScan()
            } catch {
                self.finishFailedScan(message: error.localizedDescription)
            }
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        activeScanSessionID = UUID()
        scanTask?.cancel()
        scanTask = nil
        finishCancelledScan()
    }

    func selectCategory(_ category: ScanCategory?) {
        selectedCategory = category
        selectedSection = .review
    }

    func setSelection(_ isSelected: Bool, for itemID: String) {
        if isSelected {
            selectedItemIDs.insert(itemID)
        } else {
            selectedItemIDs.remove(itemID)
        }
    }

    func focusItemIDs(_ ids: Set<String>) {
        focusedItemIDs = ids
    }

    func selectRecommendedItems() {
        selectedItemIDs = Set(items.filter { $0.recommendation == .recommended }.map(\.id))
        statusMessage = "Selected \(selectedItemIDs.count) recommended items."
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    func setVisibleItemsSelected(_ isSelected: Bool) {
        let visibleIDs = Set(visibleItems.map(\.id))
        guard !visibleIDs.isEmpty else { return }

        if isSelected {
            selectedItemIDs.formUnion(visibleIDs)
            statusMessage = "Selected \(visibleIDs.count) visible items."
        } else {
            selectedItemIDs.subtract(visibleIDs)
            statusMessage = "Deselected \(visibleIDs.count) visible items."
        }
    }

    func presentCleanupSheet() {
        let plan = cleanupCoordinator.makePlan(items: items, selectedIDs: selectedItemIDs, rules: rules)
        guard !plan.items.isEmpty else { return }
        cleanupPlan = plan
        cleanupSheetSource = .bulk
        isCleanupSheetPresented = true
    }

    func presentCleanupSheet(for item: ScanItem) {
        let selectionSnapshot = selectedItemIDs
        let focusSnapshot = focusedItemIDs
        selectedItemIDs.insert(item.id)
        let plan = cleanupCoordinator.makePlan(items: items, selectedIDs: [item.id], rules: rules)
        guard !plan.items.isEmpty else {
            selectedItemIDs = selectionSnapshot
            focusedItemIDs = focusSnapshot
            return
        }
        cleanupPlan = plan
        cleanupSheetSource = .singleItem(selectionSnapshot: selectionSnapshot, focusSnapshot: focusSnapshot)
        isCleanupSheetPresented = true
    }

    func executeCleanup() {
        guard let plan = cleanupPlan else { return }
        isCleanupSheetPresented = false

        Task { [weak self] in
            guard let self else { return }
            let result = cleanupCoordinator.execute(plan: plan)
            await MainActor.run {
                let succeededIDs = Set(
                    plan.items
                        .filter { result.succeededPaths.contains($0.path) }
                        .map(\.id)
                )
                applyCleanupResult(result, removedIDs: succeededIDs)
            }
        }
    }

    func dismissCleanupSheet() {
        isCleanupSheetPresented = false
        if case let .singleItem(selectionSnapshot, focusSnapshot) = cleanupSheetSource {
            selectedItemIDs = selectionSnapshot
            focusedItemIDs = focusSnapshot
        }
        cleanupSheetSource = nil
        cleanupPlan = nil
    }

    func inspect(_ item: ScanItem) {
        selectedSection = .review
        selectedCategory = nil
        searchText = ""
        focusedItemIDs = [item.id]
    }

    func reveal(_ item: ScanItem) {
        finderBridge.reveal(path: item.path)
    }

    func openFolder(for item: ScanItem) {
        finderBridge.openFolder(path: item.folderPath)
    }

    func open(_ item: ScanItem) {
        finderBridge.open(path: item.path)
    }

    func copyPath(of item: ScanItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.path, forType: .string)
        statusMessage = "Copied path for \(item.name)."
    }

    func excludeItemFolder(_ item: ScanItem) {
        let excludedPath = item.isDirectory ? item.path : item.folderPath
        addExcludedPath(excludedPath)
        removeItemsMatchingExcludedPath(excludedPath)
        statusMessage = "Excluded \(excludedPath) from future scans."
    }

    func addExcludedPath(_ path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !normalized.isEmpty, rules.contains(where: { $0.kind == .excludedPath && $0.value == normalized }) == false else { return }
        rules.insert(UserRule(kind: .excludedPath, value: normalized), at: 0)
        persistState()
    }

    func addExcludedPattern(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, rules.contains(where: { $0.kind == .excludedPattern && $0.value == trimmed }) == false else { return }
        rules.insert(UserRule(kind: .excludedPattern, value: trimmed), at: 0)
        persistState()
    }

    func removeRule(_ rule: UserRule) {
        rules.removeAll { $0.id == rule.id }
        persistState()
    }

    func isCategoryEnabled(_ category: ScanCategory) -> Bool {
        !rules.contains(where: { $0.kind == .categoryPreference && $0.category == category && $0.value == "disabled" })
    }

    func setCategoryEnabled(_ category: ScanCategory, enabled: Bool) {
        rules.removeAll { $0.kind == .categoryPreference && $0.category == category }
        if !enabled {
            rules.insert(UserRule(kind: .categoryPreference, value: "disabled", category: category), at: 0)
        }
        persistState()
    }

    private func handle(_ event: ScanEvent) {
        switch event {
        case let .started(target):
            statusMessage = "Scanning \(target.title)…"

        case let .progress(progress):
            if shouldPublish(progress: progress) {
                flushPendingScanItems(force: false)
                scanProgress = progress
                statusMessage = progressDescription(progress)
                lastPublishedProgressAt = currentUptime
                lastPublishedProgressPhase = progress.phase
            }

        case let .item(item):
            pendingScanItems.append(item)
            if pendingScanItems.count >= scanPublishBatchSize || currentUptime - lastScanItemsFlushAt >= scanPublishInterval {
                flushPendingScanItems(force: false)
            }

        case let .completed(snapshot):
            activeScanSessionID = UUID()
            scanTask = nil
            preScanState = nil
            flushPendingScanItems(force: true)
            scanSnapshot = snapshot
            items = snapshot.items
            isScanning = false
            scanProgress = ScanProgress(
                phase: .completed,
                processedEntries: scanProgress?.processedEntries ?? snapshot.items.count,
                matchedItems: snapshot.items.count,
                currentPath: nil,
                currentCategory: nil
            )
            selectedSection = .review
            selectedItemIDs = Set(snapshot.items.filter { $0.recommendation == .recommended }.map(\.id))
            statusMessage = "Scan complete. \(snapshot.totalMatchedBytes.byteString) flagged across \(snapshot.items.count) items."
            presentCompletionBanner(for: snapshot)
            appendHistoryEntry(matchedBytes: snapshot.totalMatchedBytes, cleanedBytes: 0, itemCount: snapshot.items.count)

        case let .failed(message):
            finishFailedScan(message: message)

        case .cancelled:
            finishCancelledScan()
        }
    }

    private func captureCurrentState() -> PreScanState {
        PreScanState(
            selectedSection: selectedSection,
            selectedCategory: selectedCategory,
            items: items,
            scanSnapshot: scanSnapshot,
            selectedItemIDs: selectedItemIDs,
            focusedItemIDs: focusedItemIDs,
            lastCleanupResult: lastCleanupResult
        )
    }

    private func restorePreScanState() {
        if let preScanState {
            selectedSection = preScanState.selectedSection
            selectedCategory = preScanState.selectedCategory
            items = preScanState.items
            scanSnapshot = preScanState.scanSnapshot
            selectedItemIDs = preScanState.selectedItemIDs
            focusedItemIDs = preScanState.focusedItemIDs
            lastCleanupResult = preScanState.lastCleanupResult
        } else {
            items = []
            scanSnapshot = nil
            selectedItemIDs.removeAll()
            focusedItemIDs.removeAll()
            lastCleanupResult = nil
        }
        preScanState = nil
    }

    private func finishCancelledScan() {
        guard isScanning || scanProgress != nil || preScanState != nil else { return }
        isScanning = false
        completionPresentationTask?.cancel()
        pendingScanItems.removeAll(keepingCapacity: true)
        scanProgress = nil
        scanTask = nil
        restorePreScanState()
        statusMessage = "Scan cancelled."
    }

    private func finishFailedScan(message: String) {
        isScanning = false
        completionPresentationTask?.cancel()
        pendingScanItems.removeAll(keepingCapacity: true)
        scanProgress = nil
        scanTask = nil
        activeScanSessionID = UUID()
        restorePreScanState()
        statusMessage = "Scan failed: \(message)"
    }

    private func flushPendingScanItems(force: Bool) {
        guard !pendingScanItems.isEmpty else { return }
        if !force, currentUptime - lastScanItemsFlushAt < scanPublishInterval, pendingScanItems.count < scanPublishBatchSize {
            return
        }

        let incoming = pendingScanItems.sorted { lhs, rhs in
            if lhs.byteSize == rhs.byteSize { return lhs.path < rhs.path }
            return lhs.byteSize > rhs.byteSize
        }
        pendingScanItems.removeAll(keepingCapacity: true)
        items = mergeSortedItems(existing: items, incoming: incoming)
        lastScanItemsFlushAt = currentUptime
    }

    private func removeItemsMatchingExcludedPath(_ path: String) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let filteredItems = items.filter { item in
            let itemPath = URL(fileURLWithPath: item.path).standardizedFileURL.path
            return itemPath != normalizedPath && itemPath.hasPrefix("\(normalizedPath)/") == false
        }

        items = filteredItems
        selectedItemIDs = selectedItemIDs.filter { id in filteredItems.contains(where: { $0.id == id }) }
        focusedItemIDs = focusedItemIDs.filter { id in filteredItems.contains(where: { $0.id == id }) }

        if let snapshot = scanSnapshot {
            let updatedItems = snapshot.items.filter { item in
                let itemPath = URL(fileURLWithPath: item.path).standardizedFileURL.path
                return itemPath != normalizedPath && itemPath.hasPrefix("\(normalizedPath)/") == false
            }
            scanSnapshot = ScanSnapshot(
                target: snapshot.target,
                items: updatedItems,
                summaries: updatedItems.summaries(),
                startedAt: snapshot.startedAt,
                endedAt: .now,
                totalMatchedBytes: updatedItems.reduce(into: Int64.zero) { $0 += $1.byteSize }
            )
        }
    }

    private func applyCleanupResult(_ result: CleanupResult, removedIDs: Set<String>) {
        lastCleanupResult = result
        cleanupPlan = nil
        selectedItemIDs.subtract(removedIDs)
        focusedItemIDs.subtract(removedIDs)
        items.removeAll { removedIDs.contains($0.id) }
        if let snapshot = scanSnapshot {
            let updatedItems = snapshot.items.filter { removedIDs.contains($0.id) == false }
            scanSnapshot = ScanSnapshot(
                target: snapshot.target,
                items: updatedItems,
                summaries: updatedItems.summaries(),
                startedAt: snapshot.startedAt,
                endedAt: .now,
                totalMatchedBytes: updatedItems.reduce(into: Int64.zero) { $0 += $1.byteSize }
            )
        }

        statusMessage = result.failedItems.isEmpty
            ? "Cleaned \(result.reclaimedBytes.byteString) by moving items to Trash."
            : "Cleaned \(result.reclaimedBytes.byteString) with \(result.failedItems.count) items skipped."

        appendHistoryEntry(matchedBytes: scanSnapshot?.totalMatchedBytes ?? 0, cleanedBytes: result.reclaimedBytes, itemCount: items.count)
    }

    private func progressDescription(_ progress: ScanProgress) -> String {
        switch progress.phase {
        case .preparing:
            return "Preparing scan."
        case .inventory:
            return "Building an inventory of accessible files."
        case .detection:
            if let category = progress.currentCategory {
                return "Classifying \(category.title.lowercased())… \(progress.matchedItems) matches so far."
            }
            return "Inspecting files… \(progress.processedEntries) entries visited."
        case .aggregation:
            return "Computing category summaries."
        case .completed:
            return "Scan complete."
        }
    }

    private func loadPersistedState() async {
        let state = await historyStore.load()
        rules = state.rules
        historyEntries = state.entries
    }

    private func persistState() {
        let rules = self.rules
        let entries = self.historyEntries
        Task {
            await historyStore.save(rules: rules, entries: entries)
        }
    }

    private func appendHistoryEntry(matchedBytes: Int64, cleanedBytes: Int64, itemCount: Int) {
        let breakdown = Dictionary(uniqueKeysWithValues: categorySummaries.map { ($0.category.rawValue, $0.totalBytes) })
        let entry = ScanHistoryEntry(
            matchedBytes: matchedBytes,
            cleanedBytes: cleanedBytes,
            itemCount: itemCount,
            categoryBreakdown: breakdown
        )

        Task { [weak self] in
            guard let self else { return }
            let updatedEntries = await historyStore.append(entry: entry, existingRules: rules, existingEntries: historyEntries)
            await MainActor.run {
                self.historyEntries = updatedEntries
            }
        }
    }

    private func shouldPublish(progress: ScanProgress) -> Bool {
        if progress.phase != lastPublishedProgressPhase {
            return true
        }
        return currentUptime - lastPublishedProgressAt >= progressPublishInterval
    }

    private func mergeSortedItems(existing: [ScanItem], incoming: [ScanItem]) -> [ScanItem] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return existing }

        var merged: [ScanItem] = []
        merged.reserveCapacity(existing.count + incoming.count)

        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < existing.count && rightIndex < incoming.count {
            let left = existing[leftIndex]
            let right = incoming[rightIndex]

            if left.byteSize > right.byteSize || (left.byteSize == right.byteSize && left.path <= right.path) {
                merged.append(left)
                leftIndex += 1
            } else {
                merged.append(right)
                rightIndex += 1
            }
        }

        if leftIndex < existing.count {
            merged.append(contentsOf: existing[leftIndex...])
        }
        if rightIndex < incoming.count {
            merged.append(contentsOf: incoming[rightIndex...])
        }

        return merged
    }

    private func presentCompletionBanner(for snapshot: ScanSnapshot) {
        let presentation = ScanCompletionPresentation(
            approach: activeScanApproach,
            itemCount: snapshot.items.count,
            totalBytes: snapshot.totalMatchedBytes,
            categoryCount: snapshot.summaries.count
        )
        scanCompletionPresentation = presentation
        completionPresentationTask?.cancel()
        completionPresentationTask = Task { [weak self, presentation] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                guard self?.scanCompletionPresentation == presentation else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    self?.scanCompletionPresentation = nil
                }
            }
        }
    }

    private var currentUptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
