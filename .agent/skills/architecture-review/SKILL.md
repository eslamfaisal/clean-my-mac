---
name: architecture-review
description: Architecture and code quality audit for CleanMyMac — MVVM adherence, protocol-based DI, Swift Concurrency correctness, Sendable conformance, testability, and separation of concerns.
---

# Architecture Review Skill — CleanMyMac

Use this skill to audit code structure, architectural layers, dependency injection, testability, and Swift 6 strict concurrency compliance.

---

## 1. MVVM Layer Separation

### 1.1 Models (Domain Layer)
- [ ] All models are `struct`s — no classes with reference semantics in the domain.
- [ ] Models conform to `Codable`, `Hashable`, `Sendable` — verify no missing conformances.
- [ ] No UI imports (`SwiftUI`, `AppKit`) in model files.
- [ ] `ScanItem.id` uses the file path as identity — verify uniqueness guarantees and potential issues with path normalization.

### 1.2 ViewModels (Business Logic Layer)
- [ ] `AppViewModel` is the **single** ViewModel for the entire app (~680 lines, 24KB). Evaluate:
  - **God Object risk**: Too many responsibilities in one class?
  - Consider extracting: `ScanCoordinator`, `CleanupCoordinator` (state), `SelectionManager`, `NavigationCoordinator`.
- [ ] `@MainActor` isolation is correct but means all business logic runs on the main thread. CPU-heavy computation (sorting, filtering) should be offloaded.
- [ ] No computed properties perform side effects — verify.

### 1.3 Views (Presentation Layer)
- [ ] Views should only call ViewModel methods — no direct service access.
- [ ] Verify no business logic leaks into Views (e.g., filtering, sorting, byte formatting should be in ViewModel or Model).
- [ ] Check that Views don't hold strong references to services or stores.

### 1.4 Services (Infrastructure Layer)
- [ ] Each service defines a **protocol**: `ScanStreaming`, `CleanupCoordinating`, `PermissionProviding`.
- [ ] All protocols have corresponding stubs/mocks in the test target — verify complete coverage.
- [ ] `HistoryStore` and `FinderBridge` lack protocols — for full testability, these should be protocol-abstracted too.

---

## 2. Dependency Injection

### 2.1 Constructor Injection
- [ ] `AppViewModel.init()` accepts all dependencies via parameters with defaults.
- [ ] Verify defaults are production implementations, not test stubs.
- [ ] No singletons or `static let shared` patterns exist (except pure utility types).

### 2.2 Testability
- [ ] All injected protocols allow stub/mock implementations.
- [ ] Verify tests use `StubPermissionCenter`, `StubScanner`, `MockCleanupCoordinator` — not production services.
- [ ] `HistoryStore` accepts a `folderName` for test isolation — verify each test uses a unique folder.

---

## 3. Swift Concurrency & Sendable

### 3.1 Sendable Conformance
- [ ] All model structs are `Sendable` ✓ — but verify computed properties don't capture non-Sendable state.
- [ ] `ScannerConfiguration`, `ScanClassifier`, `FileSystemScanner` are `Sendable` ✓.
- [ ] `CleanupCoordinator` is a struct conforming to `CleanupCoordinating: Sendable` ✓.
- [ ] `HistoryStore` — check if actor-isolated or `Sendable`. If it uses `FileManager` internally, ensure thread safety.

### 3.2 Actor Isolation
- [ ] `AppViewModel` is `@MainActor`. Confirm:
  - No `nonisolated` computed properties access `@Published` state.
  - `deinit` cancels `scanTask` — verify this is safe from `@MainActor` context.
  - Any `Task` closures that capture `self` use `[weak self]` to prevent retain cycles.

### 3.3 Strict Concurrency (Swift 6)
- [ ] `Package.swift` uses `swift-tools-version: 6.2`. Full strict concurrency is enforced.
- [ ] Verify **no** compiler warnings for:
  - Sending non-Sendable types across actor boundaries.
  - Implicitly captured mutable state.
  - Main actor isolated property access from non-isolated context.

---

## 4. Error Handling

### 4.1 Scan Errors
- [ ] `ScanEvent.failed(String)` propagates error messages. Verify:
  - Error messages are user-friendly, not raw system error strings.
  - `finishFailedScan(message:)` restores pre-scan state cleanly.
- [ ] `CancellationError` is caught separately from general errors — correct ✓.

### 4.2 Cleanup Errors
- [ ] `CleanupResult.failedItems` captures per-item failure reasons. Verify the UI surfaces these clearly.
- [ ] No cleanup error is silently swallowed.

### 4.3 Persistence Errors
- [ ] `HistoryStore.load()` and `.save()` — check if JSON decoding errors are handled or silently caught.
- [ ] Corrupt JSON should not crash the app — fallback to empty state.

---

## 5. Test Coverage

### 5.1 Current Test Suite
| Test | Layer | Coverage |
|---|---|---|
| `testDismissSingleItemCleanupRestoresPreviousSelection` | ViewModel | Selection state management |
| `testCancelScanRestoresStableResultsAndIgnoresLateEvents` | ViewModel | Scan cancellation |
| `testViewModelRetainsFailedCleanupItems` | ViewModel | Cleanup failure handling |
| `testScannerCapturesNodeModulesAsSingleDirectoryFinding` | Service | Scanner classification |
| `testScannerHonorsExcludedPaths` | Service | Exclusion rules |
| `testScannerDoesNotFlagDeveloperManifestsAsInstallers` | Service | False positive prevention |
| `testCleanupPlanAccumulatesWarningsAndBytes` | Service | Cleanup planning |
| `testScannerClassifiesBuildAndInstallerArtifacts` | Service | Multi-toolchain classification |
| `testScannerClassifiesAdditionalDeveloperToolingFolders` | Service | Extended toolchain coverage |

### 5.2 Missing Test Coverage
- [ ] **ScanClassifier** unit tests — isolated classifier tests without FileManager.
- [ ] **ScannerConfiguration** — `shouldSkipTraversal`, `globMatch`, `categoryIsDisabled`.
- [ ] **PermissionCenter** — mock FileManager to test FDA detection logic.
- [ ] **HistoryStore** — persistence round-trip, corrupt file recovery.
- [ ] **FinderBridge** — verify NSWorkspace calls (mock-based).
- [ ] **AppFormatting** — byte formatting edge cases (0 bytes, negative, Int64.max, TB-scale).
- [ ] **View snapshot tests** — no UI tests exist. Consider using `XCTest` preview snapshots.

---

## 6. Code Quality Metrics

```bash
# Lines of code per file
find Sources/ -name "*.swift" -exec wc -l {} + | sort -rn | head -20

# Cyclomatic complexity hotspots (look for long switch statements, deep nesting)
grep -c "case \." Sources/clean-my-mac/Services/Scanning/ScanClassifier.swift

# Verify no force unwraps
grep -rn '![^=]' Sources/ --include="*.swift" | grep -v '//' | grep -v 'import' | grep -v 'XCTAssert'

# Verify no print statements (use os_log or Logger instead)
grep -rn 'print(' Sources/ --include="*.swift"

# Check for TODO/FIXME/HACK markers
grep -rn 'TODO\|FIXME\|HACK\|TEMP' Sources/ --include="*.swift"
```

---

## 7. Refactoring Recommendations

### High Priority
1. **Split AppViewModel** (~680 lines) into focused coordinators:
   - `ScanCoordinator` — scan lifecycle, progress, cancellation
   - `SelectionManager` — item selection, focus, bulk operations
   - `NavigationCoordinator` — section navigation, sheet presentation
2. **Protocol-abstract `HistoryStore` and `FinderBridge`** for full testability.

### Medium Priority
3. **Extract `ScanClassifier` rules into configuration** — move magic strings and path patterns to a `ScanRules.json` or constant file for easier maintenance.
4. **Add structured logging** — `os.Logger` for scan events, cleanup actions, permission checks (useful for debugging user-reported issues).

### Low Priority
5. **Consider `@Observable` macro** (macOS 14+) to replace `ObservableObject` and reduce `@Published` boilerplate.
6. **Add doc comments** to all public protocols and ViewModel methods.
