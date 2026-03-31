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
        let scanSnapshot: ScanSnapshot?
        let selectedItemIDs: Set<String>
        let focusedItemIDs: Set<String>
        let lastCleanupResult: CleanupResult?
    }

    // MARK: - Published Properties

    @Published var selectedSection: AppSection = .dashboard
    @Published var permissionSnapshot: PermissionSnapshot
    @Published var scanSnapshot: ScanSnapshot?
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

    /// Paginated items loaded from SQLite for display. NOT the full result set.
    @Published var loadedItems: [ScanItem] = []
    /// Total number of items in the database matching current filters.
    @Published var totalItemCount: Int = 0
    /// Whether more items can be loaded from the database.
    @Published var hasMoreItems: Bool = false
    /// Category summaries computed from SQLite GROUP BY query.
    @Published var categorySummariesCache: [CategorySummary] = []

    // MARK: - Private State

    private let permissionCenter: PermissionProviding
    private let scanner: ScanStreaming
    private let cleanupCoordinator: any CleanupCoordinating
    private let historyStore: HistoryStore
    private let finderBridge: FinderBridge
    private let resultStore: ScanResultStoring
    private var scanTask: Task<Void, Never>?
    private var activeScanSessionID = UUID()
    private var preScanState: PreScanState?
    private var cleanupSheetSource: CleanupSheetSource?
    private var completionPresentationTask: Task<Void, Never>?

    // Batch insert buffer: items accumulate here before being flushed to SQLite.
    private var pendingInsertBatch: [ScanItem] = []
    private let insertBatchSize = 200
    private let insertFlushInterval: TimeInterval = 0.25
    private var lastInsertFlushAt: TimeInterval = 0

    // Pagination state
    private var currentPageOffset: Int = 0
    private let pageSize = 50

    // Progress throttling
    private let progressPublishInterval: TimeInterval = 0.12
    private var lastPublishedProgressAt: TimeInterval = 0
    private var lastPublishedProgressPhase: ScanPhase?

    init(
        permissionCenter: PermissionProviding = PermissionCenter(),
        scanner: ScanStreaming? = nil,
        cleanupCoordinator: any CleanupCoordinating = CleanupCoordinator(),
        historyStore: HistoryStore = HistoryStore(),
        finderBridge: FinderBridge = FinderBridge(),
        resultStore: ScanResultStoring = ScanResultStore()
    ) {
        self.permissionCenter = permissionCenter
        self.cleanupCoordinator = cleanupCoordinator
        self.historyStore = historyStore
        self.finderBridge = finderBridge
        self.resultStore = resultStore
        self.permissionSnapshot = permissionCenter.snapshot()

        // Build scanner with the database path excluded from scanning
        let configuration = ScannerConfiguration.default(databasePath: resultStore.databasePath)
        self.scanner = scanner ?? FileSystemScanner(configuration: configuration)

        Task { [weak self] in
            await self?.loadPersistedState()
        }
    }

    deinit {
        scanTask?.cancel()
    }

    // MARK: - Computed Properties (database-backed)

    /// Items currently loaded for display. The main list shows these.
    var visibleItems: [ScanItem] {
        loadedItems
    }

    var selectedInspectorItem: ScanItem? {
        if let focusedID = focusedItemIDs.first {
            return loadedItems.first(where: { $0.id == focusedID })
                ?? resultStore.fetchItems(ids: [focusedID]).first
        }
        if let selectedID = selectedItemIDs.first {
            return loadedItems.first(where: { $0.id == selectedID })
                ?? resultStore.fetchItems(ids: [selectedID]).first
        }
        return nil
    }

    var categorySummaries: [CategorySummary] {
        categorySummariesCache
    }

    var topOffenders: [ScanItem] {
        resultStore.topOffenders(limit: 8)
    }

    var selectedReclaimableBytes: Int64 {
        resultStore.selectedReclaimableBytes(ids: selectedItemIDs)
    }

    var allVisibleItemsSelected: Bool {
        let visibleIDs = Set(loadedItems.map(\.id))
        guard !visibleIDs.isEmpty else { return false }
        return visibleIDs.isSubset(of: selectedItemIDs)
    }

    var recommendedItemCount: Int {
        resultStore.recommendedItemCount()
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
            return "\(snapshot.itemCount.formatted()) items · \(snapshot.totalMatchedBytes.byteString)"
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
                return "\(snapshot.itemCount.formatted()) findings across \(categorySummaries.count.formatted()) categories"
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

    // MARK: - Permissions

    func refreshPermissions() {
        permissionSnapshot = permissionCenter.snapshot()
    }

    func openSystemSettings(for requirement: PermissionRequirement) {
        permissionCenter.openSystemSettings(for: requirement)
    }

    // MARK: - Scan Setup

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

    // MARK: - Scan Execution

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

        // Reset SQLite database for new scan
        try? resultStore.resetForNewScan()

        // Reset batch insert state
        pendingInsertBatch.removeAll(keepingCapacity: true)
        lastInsertFlushAt = currentUptime
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

        // Clear paginated display
        loadedItems.removeAll()
        totalItemCount = 0
        hasMoreItems = false
        categorySummariesCache = []
        currentPageOffset = 0

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

    // MARK: - Selection & Navigation

    func selectCategory(_ category: ScanCategory?) {
        selectedCategory = category
        selectedSection = .review
        reloadCurrentPage()
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
        // Fetch all recommended item IDs from SQLite
        let recommendedItems = resultStore.fetchPage(
            category: nil,
            searchText: nil,
            offset: 0,
            limit: FileSystemScanner.maxMatchedItems
        ).filter { $0.recommendation == .recommended }
        selectedItemIDs = Set(recommendedItems.map(\.id))
        statusMessage = "Selected \(selectedItemIDs.count) recommended items."
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    func setVisibleItemsSelected(_ isSelected: Bool) {
        let visibleIDs = Set(loadedItems.map(\.id))
        guard !visibleIDs.isEmpty else { return }

        if isSelected {
            selectedItemIDs.formUnion(visibleIDs)
            statusMessage = "Selected \(visibleIDs.count) visible items."
        } else {
            selectedItemIDs.subtract(visibleIDs)
            statusMessage = "Deselected \(visibleIDs.count) visible items."
        }
    }

    // MARK: - Pagination

    func loadMoreItems() {
        guard hasMoreItems, !isScanning else { return }
        currentPageOffset += pageSize
        let nextPage = resultStore.fetchPage(
            category: selectedCategory,
            searchText: searchText.isEmpty ? nil : searchText,
            offset: currentPageOffset,
            limit: pageSize
        )
        loadedItems.append(contentsOf: nextPage)
        hasMoreItems = nextPage.count == pageSize
    }

    /// Called when search text or category filter changes.
    func reloadCurrentPage() {
        currentPageOffset = 0
        let searchQuery = searchText.isEmpty ? nil : searchText
        loadedItems = resultStore.fetchPage(
            category: selectedCategory,
            searchText: searchQuery,
            offset: 0,
            limit: pageSize
        )
        totalItemCount = resultStore.totalCount(
            category: selectedCategory,
            searchText: searchQuery
        )
        hasMoreItems = loadedItems.count == pageSize
    }

    // MARK: - Cleanup

    func presentCleanupSheet() {
        let selectedItems = resultStore.fetchItems(ids: selectedItemIDs)
        let plan = cleanupCoordinator.makePlan(items: selectedItems, selectedIDs: selectedItemIDs, rules: rules)
        guard !plan.items.isEmpty else { return }
        cleanupPlan = plan
        cleanupSheetSource = .bulk
        isCleanupSheetPresented = true
    }

    func presentCleanupSheet(for item: ScanItem) {
        let selectionSnapshot = selectedItemIDs
        let focusSnapshot = focusedItemIDs
        selectedItemIDs.insert(item.id)
        let plan = cleanupCoordinator.makePlan(items: [item], selectedIDs: [item.id], rules: rules)
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

        let coordinator = cleanupCoordinator
        let store = resultStore
        Task.detached {
            let result = coordinator.execute(plan: plan)
            let succeededPaths = Set(
                plan.items
                    .filter { result.succeededPaths.contains($0.path) }
                    .map(\.path)
            )
            // Delete cleaned items from SQLite
            try? store.deleteItems(paths: succeededPaths)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.applyCleanupResult(result, removedIDs: succeededPaths)
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

    // MARK: - Item Actions

    func inspect(_ item: ScanItem) {
        selectedSection = .review
        selectedCategory = nil
        searchText = ""
        focusedItemIDs = [item.id]
        reloadCurrentPage()
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
        try? resultStore.deleteItemsMatching(excludedPath: excludedPath)
        refreshAfterDataChange()
        statusMessage = "Excluded \(excludedPath) from future scans."
    }

    // MARK: - Rules

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

    // MARK: - Event Handling

    private func handle(_ event: ScanEvent) {
        switch event {
        case let .started(target):
            statusMessage = "Scanning \(target.title)…"

        case let .progress(progress):
            if shouldPublish(progress: progress) {
                scanProgress = progress
                statusMessage = progressDescription(progress)
                lastPublishedProgressAt = currentUptime
                lastPublishedProgressPhase = progress.phase
            }

        case let .item(item):
            // Buffer items for batch SQLite insertion
            pendingInsertBatch.append(item)
            if pendingInsertBatch.count >= insertBatchSize ||
               currentUptime - lastInsertFlushAt >= insertFlushInterval {
                flushPendingInserts()
            }

        case let .completed(snapshot):
            // Flush any remaining buffered items
            flushPendingInserts()

            activeScanSessionID = UUID()
            scanTask = nil
            preScanState = nil

            // Build the final snapshot with summaries from SQLite
            let summaries = resultStore.categorySummaries()
            let finalItemCount = resultStore.itemCount()
            let finalTotalBytes = resultStore.totalMatchedBytes()
            let finalSnapshot = ScanSnapshot(
                target: snapshot.target,
                itemCount: finalItemCount,
                summaries: summaries,
                startedAt: snapshot.startedAt,
                endedAt: snapshot.endedAt,
                totalMatchedBytes: finalTotalBytes
            )

            scanSnapshot = finalSnapshot
            categorySummariesCache = summaries
            isScanning = false
            scanProgress = ScanProgress(
                phase: .completed,
                processedEntries: scanProgress?.processedEntries ?? finalItemCount,
                matchedItems: finalItemCount,
                currentPath: nil,
                currentCategory: nil
            )
            selectedSection = .review

            // Load first page of results sorted by size
            reloadCurrentPage()

            // Auto-select recommended items (from SQLite, not in-memory)
            let recommendedItems = resultStore.fetchPage(
                category: nil, searchText: nil, offset: 0, limit: FileSystemScanner.maxMatchedItems
            ).filter { $0.recommendation == .recommended }
            selectedItemIDs = Set(recommendedItems.map(\.id))

            statusMessage = "Scan complete. \(finalTotalBytes.byteString) flagged across \(finalItemCount) items."
            presentCompletionBanner(for: finalSnapshot)
            appendHistoryEntry(matchedBytes: finalTotalBytes, cleanedBytes: 0, itemCount: finalItemCount)

        case let .failed(message):
            flushPendingInserts()
            finishFailedScan(message: message)

        case .cancelled:
            finishCancelledScan()
        }
    }

    // MARK: - Batch Insert to SQLite

    private func flushPendingInserts() {
        guard !pendingInsertBatch.isEmpty else { return }
        let batch = pendingInsertBatch
        pendingInsertBatch.removeAll(keepingCapacity: true)
        lastInsertFlushAt = currentUptime

        // Insert on background to avoid blocking main thread
        let store = resultStore
        Task.detached(priority: .utility) {
            try? store.insertBatch(batch)
        }
    }

    // MARK: - State Management

    private func captureCurrentState() -> PreScanState {
        PreScanState(
            selectedSection: selectedSection,
            selectedCategory: selectedCategory,
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
            scanSnapshot = preScanState.scanSnapshot
            selectedItemIDs = preScanState.selectedItemIDs
            focusedItemIDs = preScanState.focusedItemIDs
            lastCleanupResult = preScanState.lastCleanupResult
            reloadCurrentPage()
        } else {
            loadedItems = []
            totalItemCount = 0
            hasMoreItems = false
            categorySummariesCache = []
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
        pendingInsertBatch.removeAll(keepingCapacity: true)
        scanProgress = nil
        scanTask = nil
        lastPublishedProgressAt = 0
        lastPublishedProgressPhase = nil
        scanCompletionPresentation = nil
        restorePreScanState()
        statusMessage = "Scan cancelled."
    }

    private func finishFailedScan(message: String) {
        isScanning = false
        completionPresentationTask?.cancel()
        pendingInsertBatch.removeAll(keepingCapacity: true)
        scanProgress = nil
        scanTask = nil
        activeScanSessionID = UUID()
        lastPublishedProgressAt = 0
        lastPublishedProgressPhase = nil
        scanCompletionPresentation = nil
        restorePreScanState()
        statusMessage = "Scan failed: \(message)"
    }

    private func applyCleanupResult(_ result: CleanupResult, removedIDs: Set<String>) {
        lastCleanupResult = result
        cleanupPlan = nil
        selectedItemIDs.subtract(removedIDs)
        focusedItemIDs.subtract(removedIDs)

        refreshAfterDataChange()

        statusMessage = result.failedItems.isEmpty
            ? "Cleaned \(result.reclaimedBytes.byteString) by moving items to Trash."
            : "Cleaned \(result.reclaimedBytes.byteString) with \(result.failedItems.count) items skipped."

        let totalBytes = resultStore.totalMatchedBytes()
        let count = resultStore.itemCount()
        appendHistoryEntry(matchedBytes: totalBytes, cleanedBytes: result.reclaimedBytes, itemCount: count)
    }

    /// Refreshes paginated display and summaries from SQLite after data mutations.
    private func refreshAfterDataChange() {
        categorySummariesCache = resultStore.categorySummaries()
        totalItemCount = resultStore.totalCount(
            category: selectedCategory,
            searchText: searchText.isEmpty ? nil : searchText
        )
        reloadCurrentPage()

        // Update snapshot counts
        if let snapshot = scanSnapshot {
            let newCount = resultStore.itemCount()
            let newTotal = resultStore.totalMatchedBytes()
            scanSnapshot = ScanSnapshot(
                target: snapshot.target,
                itemCount: newCount,
                summaries: categorySummariesCache,
                startedAt: snapshot.startedAt,
                endedAt: .now,
                totalMatchedBytes: newTotal
            )
        }
    }

    // MARK: - Progress Helpers

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

    private func shouldPublish(progress: ScanProgress) -> Bool {
        if progress.phase != lastPublishedProgressPhase {
            return true
        }
        return currentUptime - lastPublishedProgressAt >= progressPublishInterval
    }

    // MARK: - Persistence

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

    private func presentCompletionBanner(for snapshot: ScanSnapshot) {
        let presentation = ScanCompletionPresentation(
            approach: activeScanApproach,
            itemCount: snapshot.itemCount,
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
