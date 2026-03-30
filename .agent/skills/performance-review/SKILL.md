---
name: performance-review
description: Deep performance audit for CleanMyMac — scanning speed, memory footprint, UI responsiveness, concurrency patterns, and FileManager I/O efficiency.
---

# Performance Review Skill — CleanMyMac

Use this skill to audit the app for performance regressions, inefficient I/O, excessive memory usage, and UI thread blocking.

---

## 1. File System Scanning Performance

### 1.1 Enumerator Efficiency
- [ ] Verify `FileManager.enumerator` uses the **minimum required** `URLResourceKey` set. Extra keys cause unnecessary I/O syscalls.
- [ ] Confirm `skipsPackageDescendants` is set to avoid deep-diving into `.app` bundles.
- [ ] Check that `errorHandler` returns `true` to skip inaccessible paths without throwing — do **not** silently lose errors that indicate permission issues vs. broken symlinks.

### 1.2 Progress Reporting Frequency
- [ ] The scanner emits `.progress` every **300 entries** (`processedEntries % 300`). Verify this cadence does not flood `@Published` property updates on `@MainActor`.
- [ ] Profile with Instruments → SwiftUI → confirm `body` re-invocations are bounded during active scans.

### 1.3 Batch Publishing
- [ ] `pendingScanItems` flushes at `scanPublishBatchSize = 80`. Validate this batch size empirically against:
  - Quick Scan (few items) → should flush promptly, not hold items.
  - Full Mac Scan (thousands of items) → should not overwhelm the main thread with `items.sort()` after each flush.
- [ ] `flushPendingScanItems()` sorts the **entire** `items` array after each flush. This is **O(n log n)** on every batch. Consider:
  - Binary-insertion into a pre-sorted array instead.
  - Deferring sort until scan completes.

### 1.4 Directory Size Computation
- [ ] `directorySize(at:fileManager:)` enumerates **all descendants** for `recursiveExact` sizing. Confirm this is only used for small directories (logs, trash) — never for `node_modules` or `DerivedData`.
- [ ] `fastDirectoryEstimate` uses heuristic minimums. Validate that estimates don't dramatically overcount (causing user confusion about reclaimable space).

### 1.5 Task Cancellation Responsiveness
- [ ] `Task.checkCancellation()` is called inside every loop iteration. Verify there are no long-running blocking calls *between* cancellation checks (e.g., `directorySize` doing a full recursive walk without intermediate checks).
- [ ] Confirm `activeScanSessionID` guard correctly drops stale events after re-scan.

---

## 2. Memory & Allocations

### 2.1 Item Dictionary Growth
- [ ] `itemsByPath: [String: ScanItem]` in `performScan` accumulates all matched items. For a Full Mac scan, this could be thousands of entries. Confirm memory stays bounded — no leaked references.
- [ ] After scan completes, `itemsByPath` goes out of scope. Verify no strong reference cycle keeps it alive.

### 2.2 Published Array Copies
- [ ] `@Published var items: [ScanItem]` is a value type array. Every mutation triggers a full copy + SwiftUI diff. Confirm:
  - `items.append(contentsOf:)` + `items.sort()` is not duplicated across multiple callsites.
  - `applyCleanupResult` and `removeItemsMatchingExcludedPath` don't trigger redundant re-renders.

### 2.3 Snapshot Duplication
- [ ] `ScanSnapshot` stores a **full copy** of `[ScanItem]`. After scan, both `scanSnapshot.items` and `items` hold the same data. Consider whether the snapshot should store only summaries + totals, with `items` being the single source of truth.

---

## 3. UI Responsiveness

### 3.1 Main Thread Blocking
- [ ] `executeCleanup()` calls `cleanupCoordinator.execute(plan:)` inside a `Task`. Verify the coordinator's `FileManager.trashItem` calls happen **off** the main actor (`Task.detached` or nonisolated context).
- [ ] `chooseCustomScanFolder()` calls `NSOpenPanel.runModal()` synchronously. This is correct for AppKit panels but confirm it doesn't deadlock with `@MainActor` isolation.

### 3.2 Computed Properties
- [ ] `visibleItems` filters the full `items` array on every access. If used in `List` or `ForEach`, this recomputes on every SwiftUI body evaluation. Consider caching.
- [ ] `categorySummaries` falls back to `items.summaries()` which iterates all items × all categories. This is O(items × categories) on every access.
- [ ] `selectedReclaimableBytes` iterates all items with a filter + reduce. Should be memoized or computed incrementally.

### 3.3 SwiftUI View Granularity
- [ ] Verify large views (DashboardView at 15KB, ReviewWorkspaceView at 15KB) are decomposed into extracted subviews so SwiftUI doesn't re-diff the entire tree on minor state changes.
- [ ] Confirm `@ObservedObject` / `@StateObject` boundaries are correct — a single `AppViewModel` driving the entire app means **any** property change triggers a full re-evaluation of all observing views.

---

## 4. Concurrency Correctness

### 4.1 Data Race Safety
- [ ] `AppViewModel` is `@MainActor` — all mutations happen on the main thread. Verify no `nonisolated` or `Task.detached` closures mutate `@Published` properties without `await MainActor.run {}`.
- [ ] `FileSystemScanner` is `Sendable`. Confirm its `ScannerConfiguration` and `ScanClassifier` are also `Sendable` with no mutable shared state.

### 4.2 Task Lifecycle
- [ ] `scanTask` is stored as `Task<Void, Never>?`. Confirm:
  - Starting a new scan cancels the previous `scanTask`.
  - `deinit` cancels `scanTask` (already done ✓).
  - `cancelScan()` invalidates `activeScanSessionID` **before** cancelling the task to prevent race conditions.

### 4.3 AsyncThrowingStream Cleanup
- [ ] `continuation.onTermination` cancels the detached task. Verify no resource leaks if the stream is dropped without exhaustion.
- [ ] Confirm `continuation.finish()` is called in **all** paths (success, cancellation, error).

---

## 5. Verification Commands

```bash
# Build in release mode to check optimized performance
swift build -c release --scratch-path .build

# Run tests to validate no regressions
swift test --scratch-path .build

# Profile with Instruments (manual step)
# Open Instruments → Time Profiler → attach to CleanMyMac process
# Run a Full Mac Scan and inspect hotspots
```
