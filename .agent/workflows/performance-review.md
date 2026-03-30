---
description: Run a focused performance audit on scanning speed, memory, and UI responsiveness
---

# Performance Review Workflow

Run this workflow to identify performance bottlenecks in scanning, memory usage, and UI responsiveness.

## Steps

1. **Read the Performance Skill** — Load the full checklist:
   - Read `.agent/skills/performance-review/SKILL.md`

2. **Build in Release Mode** — Performance analysis should use optimized builds:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift build -c release --scratch-path .build 2>&1 | tail -5
```

3. **Audit Scanning I/O** — Review `FileSystemScanner.swift`:
   - Check URLResourceKey set for minimal necessary keys
   - Review progress reporting frequency (every 300 entries)
   - Evaluate batch publishing size (80 items)
   - Assess `flushPendingScanItems()` sort cost — O(n log n) per batch

4. **Audit Memory Patterns** — Review `AppViewModel.swift`:
   - Check `@Published` array mutation patterns
   - Evaluate snapshot duplication (items stored in both `items` and `scanSnapshot.items`)
   - Look for retain cycles in `Task { [weak self] in ... }` closures

5. **Audit UI Responsiveness** — Review Views:
   - Check computed property costs (`visibleItems`, `categorySummaries`, `selectedReclaimableBytes`)
   - Evaluate view decomposition (large 15KB view files)
   - Verify main-thread blocking calls

6. **Audit Concurrency** — Review async patterns:
   - Verify `Task.checkCancellation()` placement
   - Check `AsyncThrowingStream` lifecycle (no leaks)
   - Confirm `@MainActor` isolation correctness

7. **Run Tests** — Ensure performance changes don't break behavior:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift test --scratch-path .build 2>&1 | tail -15
```

8. **Generate Performance Report** — Document findings with severity and recommendations.
