---
name: test-coverage-review
description: Test quality and coverage audit for CleanMyMac — unit tests, integration tests, edge cases, mock completeness, and test infrastructure patterns.
---

# Test Coverage Review Skill — CleanMyMac

Use this skill to audit the test suite for coverage gaps, test quality, mock completeness, and missing edge case scenarios.

---

## 1. Test Infrastructure

### 1.1 Test Helpers
- [ ] `TestFixture` creates temp directories and files for file system tests — good pattern.
- [ ] Verify `TestFixture.cleanup()` is called in `defer` blocks to prevent temp file leaks.
- [ ] `StubPermissionCenter`, `StubScanner`, `MockCleanupCoordinator`, `DelayedScanner` — verify these cover all protocol methods.

### 1.2 Test Isolation
- [ ] `HistoryStore(folderName:)` uses UUID-based folder names for isolation ✓.
- [ ] Verify test artifacts are cleaned up — no persistent state bleeds across test runs.
- [ ] No shared mutable state between tests.

---

## 2. Coverage Analysis by Component

### 2.1 Models (`Sources/clean-my-mac/Models/`)
| File | Tests Exist | Missing Coverage |
|---|---|---|
| `ScanModels.swift` | Partial (via scanner tests) | `ScanItem.summaries()`, `ScanApproach.buildTarget`, `ScanTarget` factory methods |
| `CleanupModels.swift` | Partial (via coordinator tests) | `UserRule` creation, `ScanHistoryEntry` encoding/decoding |
| `PermissionModels.swift` | ❌ None | `PermissionSnapshot.requiresAttention`, `missingRequirements` |
| `AppFormatting.swift` | ❌ None | Byte formatting edge cases |

### 2.2 Services (`Sources/clean-my-mac/Services/`)
| File | Tests Exist | Missing Coverage |
|---|---|---|
| `FileSystemScanner.swift` | ✅ Good | Symlink handling, permission errors, very large directories |
| `ScanClassifier.swift` | Partial (via scanner) | Isolated classifier unit tests, edge-case paths |
| `ScannerConfiguration.swift` | Partial (via scanner) | `globMatch` patterns, `shouldSkipTraversal` edge cases |
| `CleanupCoordinator.swift` | ✅ Good | Concurrent cleanup, path with special characters |
| `PermissionCenter.swift` | ❌ None | FDA detection, folder state checks |
| `HistoryStore.swift` | ❌ None | Load/save round-trip, corrupt file recovery |
| `FinderBridge.swift` | ❌ None | Verify NSWorkspace calls |

### 2.3 ViewModels (`Sources/clean-my-mac/ViewModels/`)
| Feature Area | Tests Exist | Missing Coverage |
|---|---|---|
| Scan lifecycle | ✅ Start, cancel | Re-scan during active scan, failed scan recovery |
| Selection management | ✅ Basic | Bulk selection, category filter + selection interaction |
| Cleanup flow | ✅ Good | Concurrent cleanup requests, cleanup during scan |
| Exclusion rules | ❌ None | Add/remove rules, pattern matching |
| History | ❌ None | Entry accumulation, persistence sync |
| Navigation | ❌ None | Section switching, sheet presentation/dismissal |
| Computed properties | ❌ None | `visibleItems`, `categorySummaries`, `topOffenders`, `toolbarHeadline` |

---

## 3. Critical Missing Tests

### 3.1 Must-Have Tests
```swift
// 1. ScanClassifier isolation — test classification decisions without FileManager
func testClassifyNodeModulesDirectory()
func testClassifyDerivedDataDirectory()
func testClassifyLogFile()
func testClassifyLargeFile()
func testClassifyOldFile()
func testClassifyApplicationBuild()
func testIgnoreSafeDeveloperManifests()

// 2. ScannerConfiguration edge cases
func testGlobMatchSimpleWildcard()
func testGlobMatchNoMatch()
func testGlobMatchCaseInsensitive()
func testShouldSkipProtectedPaths()
func testShouldSkipExcludedPaths()
func testShouldSkipExcludedPatterns()
func testShouldNotSkipNormalPaths()

// 3. AppFormatting
func testByteStringZeroBytes()
func testByteStringKilobytes()
func testByteStringMegabytes()
func testByteStringGigabytes()
func testByteStringTerabytes()

// 4. PermissionSnapshot
func testRequiresAttentionWhenFDAMissing()
func testDoesNotRequireAttentionWhenGranted()
func testMissingRequirementsFiltering()

// 5. HistoryStore round-trip
func testSaveAndLoadRules()
func testSaveAndLoadEntries()
func testLoadCorruptFileReturnsDefaults()

// 6. ViewModel exclusion rules
func testAddExcludedPathRemovesMatchingItems()
func testAddDuplicateExcludedPathIsNoop()
func testAddExcludedPatternNormalization()
func testRemoveRulePersists()
```

### 3.2 Edge Case Tests
```swift
// File system edge cases
func testScannerHandlesEmptyDirectory()
func testScannerHandlesDeeplyNestedPath()
func testScannerHandlesSpecialCharactersInPath()
func testScannerHandlesUnicodeFilenames()
func testScannerHandlesZeroByteFiles()
func testScannerSkipsSymlinkLoops()

// ViewModel edge cases
func testStartScanWhileAlreadyScanning()
func testCleanupWithEmptySelection()
func testSelectRecommendedItemsWithNoRecommended()
func testCategoryFilterWithNoMatchingItems()
func testSearchFilterCaseInsensitive()
```

---

## 4. Test Quality Checklist

- [ ] All tests have descriptive names following `test<Behavior>When<Condition>` pattern.
- [ ] No test depends on execution order.
- [ ] Async tests use appropriate timeouts — not just `Task.sleep` with magic numbers.
- [ ] No flaky tests due to timing — `DelayedScanner` sleep durations are adequate.
- [ ] Assertions are specific — using `XCTAssertEqual` over `XCTAssertTrue` where applicable.
- [ ] Each test verifies ONE behavior — no multi-assertion tests testing unrelated things.

---

## 5. Verification Commands

```bash
# Run all tests
swift test --scratch-path .build

# Run tests with verbose output
swift test --scratch-path .build --verbose

# Count test methods
grep -c "func test" Tests/CleanMyMacAppTests/CleanMyMacAppTests.swift

# Check for test file organization
find Tests/ -name "*.swift" -type f
```
