---
description: Audit and improve test coverage — identify gaps, generate missing tests, and verify quality
---

# Test Coverage Review Workflow

Run this workflow to identify test coverage gaps and generate missing test cases.

## Steps

1. **Read the Test Coverage Skill** — Load the full checklist:
   - Read `.agent/skills/test-coverage-review/SKILL.md`

2. **Run Existing Tests** — Baseline pass/fail status:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift test --scratch-path .build 2>&1 | tail -20
```

3. **Count Current Tests** — Establish baseline:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && echo "=== Test Count ===" && grep -c "func test" Tests/CleanMyMacAppTests/CleanMyMacAppTests.swift && echo "=== Test Files ===" && find Tests/ -name "*.swift" -type f
```

4. **Analyze Coverage Gaps** — Cross-reference source files against tests:
   - Models: `ScanModels.swift`, `CleanupModels.swift`, `PermissionModels.swift`, `AppFormatting.swift`
   - Services: `FileSystemScanner`, `ScanClassifier`, `ScannerConfiguration`, `CleanupCoordinator`, `PermissionCenter`, `HistoryStore`, `FinderBridge`
   - ViewModel: `AppViewModel` — selection management, exclusion rules, history, navigation, computed properties

5. **Identify Critical Missing Tests** — Prioritize:
   - P0: ScanClassifier isolation tests (classification decisions without FileManager)
   - P0: ScannerConfiguration edge cases (glob matching, protected paths)
   - P1: AppFormatting byte string tests
   - P1: HistoryStore persistence round-trip
   - P1: PermissionSnapshot computed properties
   - P2: ViewModel exclusion rule tests
   - P2: ViewModel computed property tests

6. **Generate Missing Tests** — Write test code for the highest-priority gaps.

7. **Run Updated Tests** — Verify all tests pass:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift test --scratch-path .build 2>&1 | tail -20
```

8. **Generate Coverage Report** — Document current vs. target coverage by component.
