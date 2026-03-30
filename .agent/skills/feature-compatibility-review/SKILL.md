---
name: feature-compatibility-review
description: Feature compatibility audit for CleanMyMac — macOS version support, architecture compatibility, API availability, file system edge cases, and roadmap validation.
---

# Feature Compatibility Review Skill — CleanMyMac

Use this skill to audit the app's compatibility across macOS versions, architectures, file system edge cases, and feature completeness against the roadmap.

---

## 1. macOS Version Compatibility

### 1.1 Deployment Target
- [ ] `Package.swift` declares `.macOS(.v14)` (Sonoma). Verify:
  - All APIs used are available on macOS 14.0+.
  - No accidental use of macOS 15-only APIs (e.g., new SwiftUI modifiers introduced in Sequoia).
  - Grep for `@available` or `#available` checks — ensure they match the deployment target.

### 1.2 System Settings Deep Links
- [ ] `PermissionCenter.openSystemSettings()` uses `x-apple.systempreferences:` URL scheme.
  - Verify this scheme works on macOS 14 **and** macOS 15.
  - The `com.apple.preference.security` path may change between OS versions — test on both.
  - Fallback to opening System Settings.app is present — good.

### 1.3 FileManager API Compatibility
- [ ] `URL.appending(path:directoryHint:)` — introduced in macOS 13. ✅ Compatible.
- [ ] `directoryEntryCountKey` — verify availability on macOS 14.
- [ ] `trashItem(at:resultingItemURL:)` — available since macOS 10.8. ✅ Compatible.

---

## 2. Architecture Compatibility

### 2.1 Apple Silicon (arm64)
- [ ] The DMG build script targets `arm64-apple-macosx`. ✅ Primary target.
- [ ] Verify all code is pure Swift with no architecture-specific assembly or C code.

### 2.2 Intel (x86_64) — Roadmap Item
- [ ] The README roadmap lists "Intel universal binary support".
- [ ] Audit for any architecture-dependent code:
  - No `#if arch(arm64)` guards.
  - No NEON/ARM-specific intrinsics.
  - FileManager and Foundation APIs are arch-agnostic.
- [ ] To enable universal binary: update `package_dmg.sh` to build with `--arch arm64 --arch x86_64` or `--triple`.

---

## 3. File System Edge Cases

### 3.1 APFS-Specific Behavior
- [ ] **Cloned files** (APFS copy-on-write): `fileSizeKey` may report the logical size, not physical. Consider using `totalFileAllocatedSizeKey` (already used ✅).
- [ ] **Sparse files**: Verify allocated size vs logical size handling.
- [ ] **Firmlinks**: `/System/Volumes/Data` firmlink loop. Confirm the scanner doesn't traverse this infinitely.

### 3.2 Case Sensitivity
- [ ] macOS default is **case-insensitive** HFS+/APFS. Verify:
  - `lowercased()` comparisons in `ScanClassifier` handle this correctly.
  - `url.lastPathComponent.lowercased()` is used consistently.
  - No case-sensitive dictionary key collisions for `itemsByPath`.

### 3.3 Special Characters in Paths
- [ ] Paths with spaces, Unicode characters, emoji, and dots should be handled.
- [ ] `URL(fileURLWithPath:)` handles percent encoding automatically.
- [ ] Verify `standardizedFileURL.path` normalizes `//` and trailing `/`.

### 3.4 Symlinks & Aliases
- [ ] macOS Finder aliases are **not** the same as symlinks. Verify:
  - The scanner doesn't resolve Finder aliases (would require `NSURL.bookmarkData`).
  - Symlinks: `FileManager.enumerator` with default options **does** follow symlinks. This could cause:
    - Infinite loops (symlink pointing to parent).
    - Scanning outside the target scope.
  - **Recommendation**: Add `.skipsSubdirectoryDescendants` check for symlink targets or add `.skipsPackageDescendants` (already present).

### 3.5 Volumes & Mount Points
- [ ] `/Volumes/` is skipped. But what about:
  - Network volumes mounted under `/Volumes/`? → Correctly skipped.
  - APFS snapshots? → Not a traversal concern.
  - External USB drives? → Correctly skipped via `/Volumes/` guard.

---

## 4. Feature Completeness Audit

### 4.1 Implemented Features
Compare against README feature list:

| Feature | Status | Notes |
|---|---|---|
| Quick Scan | ✅ | Verify hotspot paths exist on all Macs |
| Current User Scan | ✅ | |
| Full Mac Scan | ✅ | Requires FDA |
| Specific Folder Scan | ✅ | NSOpenPanel-based |
| Smart Categorization (9 categories) | ✅ | All categories implemented in ScanClassifier |
| Risk Assessment | ✅ | Low/Medium/High |
| Recommendation Engine | ✅ | Recommended/Review/ManualInspection |
| File Inspector | ✅ | InspectorView |
| Exclusion Rules | ✅ | Path + Pattern exclusions |
| Trash-Only Deletion | ✅ | |
| Dashboard Metrics | ✅ | MetricBadge-based |
| Category Browser | ✅ | Drill-down from dashboard |
| Top Offenders Panel | ✅ | Top 8 items |
| Cleanup History | ✅ | HistoryStore persistence |
| Dark Mode Glassmorphism | ✅ | AppTheme.swift |
| Keyboard Shortcuts | ✅ | ⌘⇧R, ⌘⇧⌫ |
| Full Disk Access Detection | ✅ | PermissionCenter |
| No Network Calls | ✅ | Verify with grep |

### 4.2 Roadmap Items (Not Yet Implemented)
- [ ] Intel (x86_64) universal binary
- [ ] Developer ID code signing
- [ ] Homebrew Cask distribution
- [ ] Scheduled automatic scans
- [ ] Disk usage visualization (treemap / sunburst)
- [ ] Spotlight-style quick search
- [ ] Export scan reports (JSON / CSV)
- [ ] Localization (Arabic, German, Japanese)

### 4.3 Missing Features to Consider
- [ ] **Undo last cleanup** — restore from Trash programmatically.
- [ ] **Scan scheduling** — LaunchAgent-based periodic scans.
- [ ] **Disk space monitoring** — persistent menu bar widget showing available space.
- [ ] **Quick Look preview** — press Space on a selected item to preview.
- [ ] **Drag-out** — drag items from the review table to Finder.

---

## 5. Toolchain Detection Coverage

### 5.1 Currently Detected Toolchains
| Toolchain | Directory Patterns | File Patterns |
|---|---|---|
| Xcode | DerivedData, Archives, SourcePackages | — |
| Node.js | node_modules, .npm, .yarn, .pnpm-store | — |
| Flutter | .dart_tool, .pub-cache, flutter_build | — |
| Gradle | .gradle | — |
| CocoaPods | Pods, Library/Caches/Cocoapods | — |
| Python | .venv, venv, __pycache__,.pytest_cache,.mypy_cache | — |
| Rust | .cargo/registry, .cargo/git | — |
| Go | go/pkg/mod | — |
| Docker | Library/Containers/com.docker.docker | — |
| Terraform | .terraform, .terragrunt-cache | — |
| Bazel | bazel-out, bazel-bin, bazel-testlogs | — |
| CMake | cmakefiles, cmake-build-* | — |
| Maven | .m2/repository | — |
| Homebrew | Library/Caches/Homebrew | — |

### 5.2 Missing Toolchain Coverage
- [ ] **Ruby**: Consider `vendor/bundle`, `.bundle`, `Gemfile.lock`-adjacent gems.
- [ ] **Java (non-Gradle)**: `target/` is covered but `out/` may overlap with other tools.
- [ ] **Xcode Simulators**: `Library/Developer/CoreSimulator/Devices` — individual device data.
- [ ] **VS Code**: `.vscode/`, `~/.vscode/extensions/` — workspace caches.
- [ ] **JetBrains IDEs**: `~/.config/JetBrains/`, workspace caches.
- [ ] **Android Emulator**: `~/.android/avd/` — virtual device images.

---

## 6. Verification Commands

```bash
# Check minimum deployment target
grep -n "macOS" Package.swift

# Find any @available checks
grep -rn "@available\|#available" Sources/

# Verify no architecture-specific code
grep -rn "#if arch\|#if os" Sources/

# Test build for errors
swift build --scratch-path .build 2>&1 | head -50

# Run all tests
swift test --scratch-path .build
```
