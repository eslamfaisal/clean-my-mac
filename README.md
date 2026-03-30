<p align="center">
  <img src="Resources/BrandPreview.png" alt="CleanMyMac — Developer Disk Cleanup Studio" width="480" />
</p>

<h1 align="center">CleanMyMac</h1>

<p align="center">
  <strong>Developer Disk Cleanup Studio for macOS</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#installation">Installation</a> •
  <a href="#build-from-source">Build from Source</a> •
  <a href="#usage">Usage</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square&logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-6.2-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-purple?style=flat-square" alt="SwiftUI" />
  <img src="https://img.shields.io/github/v/release/eslamfaisal/clean-my-mac?style=flat-square&color=green" alt="Release" />
  <img src="https://img.shields.io/github/license/eslamfaisal/clean-my-mac?style=flat-square" alt="License" />
</p>

---

## Overview

**CleanMyMac** is a native macOS utility built entirely with **SwiftUI** that helps developers reclaim disk space by intelligently scanning for build artifacts, dependency caches, logs, installers, and large dormant files. Unlike aggressive cleanup tools, CleanMyMac follows a **review-first philosophy** — nothing is ever deleted without your explicit approval.

Designed for developers who accumulate gigabytes of Xcode DerivedData, `node_modules`, Gradle caches, Docker images, Homebrew leftovers, and other toolchain debris over time.

---

## Features

### 🔍 Intelligent Scanning

- **Quick Scan** — Fast pass across the most common developer hot zones (Desktop, Downloads, Documents, Library caches, logs, and dev folders)
- **Current User Scan** — Deep scan limited to your home directory
- **Full Mac Scan** — Comprehensive internal-disk scan including protected locations (with Full Disk Access)
- **Specific Folder Scan** — Targeted scan of a chosen folder or workspace

### 🏷️ Smart Categorization

Detected items are automatically classified into actionable categories:

| Category | Description |
|---|---|
| **Build Artifacts** | Generated build output (DerivedData, `.build`, `build/`, `target/`) |
| **Application Builds** | Packaged app bundles, release binaries, installers |
| **Developer Caches** | Dependency caches (`node_modules`, `.gradle`, CocoaPods, Homebrew) |
| **Large Files** | Heavy items dominating disk usage (>100 MB) |
| **Old Files** | Dormant files untouched for months |
| **Logs** | Diagnostic output, stale system and app logs |
| **Downloads & Installers** | DMGs, PKGs, ZIPs, and other installer archives |
| **Trash** | Items already in the user's Trash |
| **Other** | Additional clutter detected with lower confidence |

### 🛡️ Review-First Cleanup

- **Risk Assessment** — Each item is tagged with a risk level (Low / Medium / High)
- **Recommendation Engine** — Items marked as Recommended, Review, or Manual Inspection
- **File Inspector** — Inspect exact paths, sizes, modification dates, and the rationale behind each detection
- **Exclusion Rules** — Persistently exclude files or folders from future scans
- **Trash-Only Deletion** — All removals go through macOS Trash, never permanently deleted

### 📊 Dashboard & Analytics

- Real-time metric badges: reclaimable space, selected cleanup size, recommended items, flagged categories
- Category browser with drill-down into each detected category
- Top offenders panel highlighting the largest flagged items
- Cleanup history tracking across sessions

### 🎨 Premium UI/UX

- Dark-mode-first glassmorphism design with gradient backgrounds
- Custom app icon generated programmatically (no external assets required)
- Responsive layout adapting from compact to wide window sizes
- Keyboard shortcuts for power users (`⌘⇧R` to scan, `⌘⇧⌫` to clean)

### 🔐 Privacy & Permissions

- Full Disk Access detection with guided setup
- No network calls — everything runs 100% locally
- No telemetry, no analytics, no data collection
- Persisted settings stored in `~/Library/Application Support/`

---

## Screenshots

> Screenshots will be added after the first stable release. Run the app locally to preview the dashboard, review workspace, and scan setup.

---

## Installation

### Download DMG (Recommended)

1. Go to the [Releases](https://github.com/eslamfaisal/clean-my-mac/releases) page
2. Download the latest `CleanMyMac.dmg`
3. Open the DMG and drag **CleanMyMac.app** into your **Applications** folder
4. On first launch, right-click the app and choose **Open** (macOS Gatekeeper will block unsigned apps on the first run)
5. Grant **Full Disk Access** in `System Settings > Privacy & Security > Full Disk Access` for comprehensive scanning

### Requirements

- **macOS 14.0** (Sonoma) or later
- **Apple Silicon** (arm64) — the DMG is built for `arm64-apple-macosx`
- **Full Disk Access** (optional but recommended for deep scanning)

---

## Build from Source

### Prerequisites

- **Xcode 16+** or **Swift 6.2+** toolchain
- macOS 14.0+

### Build & Run

```bash
# Clone the repository
git clone https://github.com/eslamfaisal/clean-my-mac.git
cd clean-my-mac

# Build in debug mode
swift build --scratch-path .build

# Run the app
swift run --scratch-path .build CleanMyMac
```

Alternatively, open `Package.swift` directly in **Xcode** and run the `CleanMyMac` executable target.

### Run Tests

```bash
swift test --scratch-path .build
```

The test suite validates directory aggregation, exclusion rules, and cleanup planning logic.

### Package DMG

To create a distributable `.dmg` installer:

```bash
chmod +x scripts/package_dmg.sh
./scripts/package_dmg.sh
```

This will:
1. Generate brand assets (app icon + preview image)
2. Build a release binary for arm64
3. Create a signed `.app` bundle with `Info.plist`
4. Package everything into a compressed DMG at `dist/CleanMyMac.dmg`

---

## Usage

### 1. Grant Access

On first launch, the dashboard will show a permissions panel if Full Disk Access is not yet granted. Open:

```
System Settings > Privacy & Security > Full Disk Access
```

Enable the app manually, then return to CleanMyMac and rescan.

### 2. Choose Scan Scope

Press `⌘⇧R` or click **Scan Mac** to open the scan setup sheet. Choose from:

- ⚡ **Quick** — Hotspot folders only (~seconds)
- 👤 **Current User** — Entire home directory (~minutes)
- 💽 **Full Mac** — Whole internal volume (~longer)
- 📁 **Specific Folder** — A single chosen directory

### 3. Review Results

After scanning, switch to the **Review Workspace** tab to:

- Browse all detected items in a sortable, filterable table
- Filter by category using the chip bar
- Search by file name or path
- Inspect individual items for risk, recommendation, and rationale
- Toggle checkboxes to select items for cleanup

### 4. Clean Selected Items

Press `⌘⇧⌫` or click **Clean Selected Items** to move approved items to Trash. A confirmation sheet shows exactly what will be removed and the total reclaimable space.

### 5. History & Exclusions

- **History** — View past cleanup sessions with timestamps and reclaimed bytes
- **Exclusions** — Manage persistent rules to skip files or folders in future scans

---

## Architecture

CleanMyMac follows **MVVM** architecture with clean separation of concerns:

```
Sources/clean-my-mac/
├── App/                    # App entry point (@main)
│   └── CleanMyMacApp.swift
├── Models/                 # Domain models (pure value types)
│   ├── ScanModels.swift    # ScanTarget, ScanItem, ScanCategory, etc.
│   ├── CleanupModels.swift # CleanupPlan, CleanupResult
│   ├── PermissionModels.swift
│   └── AppFormatting.swift # Date & byte formatting utilities
├── ViewModels/             # Business logic & state management
│   └── AppViewModel.swift  # Central @MainActor ObservableObject
├── Views/                  # SwiftUI presentation layer
│   ├── AppShellView.swift  # Root navigation shell
│   ├── DashboardView.swift # Main dashboard with metrics & panels
│   ├── ReviewWorkspaceView.swift  # Item review table
│   ├── ScanSetupSheetView.swift   # Scan configuration sheet
│   ├── CleanupSheetView.swift     # Cleanup confirmation
│   ├── HistoryView.swift          # Past cleanup sessions
│   ├── ExclusionsView.swift       # Exclusion rule management
│   ├── InspectorView.swift        # File detail inspector
│   ├── SidebarView.swift          # Navigation sidebar
│   ├── AppLogoView.swift          # Programmatic logo & sparkle shapes
│   └── AppTheme.swift             # Design system (palette, glass cards, badges)
├── Services/               # Infrastructure & I/O
│   ├── Scanning/           # File system traversal & classification
│   ├── Cleanup/            # Trash-based file removal
│   ├── Finder/             # macOS Finder integration
│   ├── History/            # Persistent cleanup history
│   └── Permissions/        # Full Disk Access detection
```

### Design Principles

- **Swift Concurrency** — All async operations use `async/await` with `@MainActor` isolation
- **Value Types** — Models are `struct`s conforming to `Codable`, `Hashable`, `Sendable`
- **No External Dependencies** — Zero third-party packages; built entirely on Apple frameworks
- **Dark Mode First** — The entire UI is designed for `.preferredColorScheme(.dark)`
- **Glassmorphism Design System** — Consistent visual language via `GlassCardModifier`, `MetricBadge`, `TagPill`

---

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 6.2 |
| UI Framework | SwiftUI |
| Platform | macOS 14+ (Sonoma) |
| Architecture | MVVM |
| Concurrency | Swift Concurrency (async/await) |
| Persistence | FileManager + JSON (Application Support) |
| Dependencies | None (zero third-party packages) |
| Distribution | Ad-hoc signed DMG |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘⇧R` | Open Scan Setup |
| `⌘⇧⌫` | Clean Selected Items |

---

## Contributing

Contributions are welcome! Here's how to get started:

1. **Fork** the repository
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Commit your changes** (`git commit -m 'feat: add amazing feature'`)
4. **Push to the branch** (`git push origin feature/amazing-feature`)
5. **Open a Pull Request**

### Guidelines

- Follow existing code style and architecture patterns
- Add tests for new business logic in `Tests/CleanMyMacAppTests/`
- Keep the zero-dependency philosophy — avoid adding third-party packages
- Use Swift Concurrency (`async/await`) for all asynchronous work
- Ensure all models remain `Sendable` and thread-safe

---

## Roadmap

- [ ] Intel (x86_64) universal binary support
- [ ] Code signing with Developer ID for Gatekeeper
- [ ] Homebrew Cask distribution
- [ ] Scheduled automatic scans
- [ ] Disk usage visualization (treemap / sunburst)
- [ ] Spotlight-style quick search across scan results
- [ ] Export scan reports (JSON / CSV)
- [ ] Localization (Arabic, German, Japanese, etc.)

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Built with ❤️ using **SwiftUI** and **Swift Package Manager**
- App icon and brand assets generated programmatically — no external design tools required
- Inspired by the need to reclaim disk space after years of Xcode, Node.js, and Gradle builds

---

<p align="center">
  <sub>Made by <a href="https://github.com/eslamfaisal">Eslam Faisal</a></sub>
</p>
