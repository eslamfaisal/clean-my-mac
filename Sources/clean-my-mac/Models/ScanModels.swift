import Foundation

struct ScanTarget: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case quickHotspots
        case currentUser
        case internalVolume
        case customRoots
    }

    var kind: Kind
    var rootPaths: [String]

    static let internalVolume = ScanTarget(kind: .internalVolume, rootPaths: ["/"])

    static func quickHotspots(fileManager: FileManager = .default) -> ScanTarget {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: "Desktop", directoryHint: .isDirectory),
            home.appending(path: "Downloads", directoryHint: .isDirectory),
            home.appending(path: "Documents", directoryHint: .isDirectory),
            home.appending(path: "Library/Developer", directoryHint: .isDirectory),
            home.appending(path: "Library/Caches", directoryHint: .isDirectory),
            home.appending(path: "Library/Logs", directoryHint: .isDirectory),
        ]

        let existingPaths = candidates
            .filter { fileManager.fileExists(atPath: $0.path) }
            .map(\.path)

        return ScanTarget(kind: .quickHotspots, rootPaths: existingPaths.isEmpty ? [home.path] : existingPaths)
    }

    static func currentUser(fileManager: FileManager = .default) -> ScanTarget {
        ScanTarget(kind: .currentUser, rootPaths: [fileManager.homeDirectoryForCurrentUser.path])
    }

    static func custom(_ urls: [URL]) -> ScanTarget {
        ScanTarget(kind: .customRoots, rootPaths: urls.map(\.path))
    }

    var rootURLs: [URL] {
        rootPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var title: String {
        switch kind {
        case .quickHotspots:
            return "Quick Hotspots"
        case .currentUser:
            return "Current User"
        case .internalVolume:
            return "Internal Macintosh Volume"
        case .customRoots:
            return "Custom Roots"
        }
    }
}

enum ScanApproach: String, CaseIterable, Codable, Identifiable, Sendable {
    case quick
    case currentUser
    case fullMac
    case specificPath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick:
            return "Quick Scan"
        case .currentUser:
            return "Current User"
        case .fullMac:
            return "Full Mac"
        case .specificPath:
            return "Specific Folder"
        }
    }

    var shortLabel: String {
        switch self {
        case .quick:
            return "Quick"
        case .currentUser:
            return "User"
        case .fullMac:
            return "Full"
        case .specificPath:
            return "Folder"
        }
    }

    var symbolName: String {
        switch self {
        case .quick:
            return "bolt.fill"
        case .currentUser:
            return "person.crop.circle.fill"
        case .fullMac:
            return "internaldrive.fill"
        case .specificPath:
            return "folder.fill.badge.plus"
        }
    }

    var summary: String {
        switch self {
        case .quick:
            return "Fast pass across the most common clutter and developer hot zones."
        case .currentUser:
            return "Deep scan limited to the current user's home directory."
        case .fullMac:
            return "Full internal-disk scan across the Mac, including protected locations when allowed."
        case .specificPath:
            return "Targeted scan of one chosen folder or workspace."
        }
    }

    var detail: String {
        switch self {
        case .quick:
            return "Best for frequent cleanup runs. Focuses on Desktop, Downloads, Documents, Library caches, logs, and developer folders."
        case .currentUser:
            return "Scans your full home directory and personal development data without traversing the rest of the system."
        case .fullMac:
            return "The most comprehensive mode. Use it when you want the broadest classification across the internal drive."
        case .specificPath:
            return "Useful for a single workspace, drive folder, or export directory when you do not want a system-wide pass."
        }
    }

    var speedLabel: String {
        switch self {
        case .quick:
            return "Fast"
        case .currentUser:
            return "Balanced"
        case .fullMac:
            return "Deep"
        case .specificPath:
            return "Targeted"
        }
    }

    var coverageLabel: String {
        switch self {
        case .quick:
            return "Hotspots"
        case .currentUser:
            return "Home Folder"
        case .fullMac:
            return "Whole Internal Disk"
        case .specificPath:
            return "Chosen Folder"
        }
    }

    func buildTarget(customPath: String?, fileManager: FileManager = .default) -> ScanTarget? {
        switch self {
        case .quick:
            return .quickHotspots(fileManager: fileManager)
        case .currentUser:
            return .currentUser(fileManager: fileManager)
        case .fullMac:
            return .internalVolume
        case .specificPath:
            guard let customPath, !customPath.isEmpty else { return nil }
            return .custom([URL(fileURLWithPath: customPath, isDirectory: true)])
        }
    }

    func previewPaths(customPath: String?, fileManager: FileManager = .default) -> [String] {
        switch self {
        case .quick:
            return ScanTarget.quickHotspots(fileManager: fileManager).rootPaths
        case .currentUser:
            return [fileManager.homeDirectoryForCurrentUser.path]
        case .fullMac:
            return ["/"]
        case .specificPath:
            if let customPath, !customPath.isEmpty {
                return [customPath]
            }
            return ["Choose a folder to scan"]
        }
    }
}

enum ScanCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case buildArtifacts
    case applicationBuilds
    case devCaches
    case largeFiles
    case oldFiles
    case logs
    case downloadsInstallers
    case trash
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildArtifacts:
            return "Build Artifacts"
        case .applicationBuilds:
            return "Application Builds"
        case .devCaches:
            return "Developer Caches"
        case .largeFiles:
            return "Large Files"
        case .oldFiles:
            return "Old Files"
        case .logs:
            return "Logs"
        case .downloadsInstallers:
            return "Downloads & Installers"
        case .trash:
            return "Trash"
        case .other:
            return "Other Review Items"
        }
    }

    var symbolName: String {
        switch self {
        case .buildArtifacts:
            return "hammer.circle.fill"
        case .applicationBuilds:
            return "shippingbox.circle.fill"
        case .devCaches:
            return "externaldrive.fill.badge.person.crop"
        case .largeFiles:
            return "internaldrive.fill"
        case .oldFiles:
            return "clock.arrow.circlepath"
        case .logs:
            return "text.append"
        case .downloadsInstallers:
            return "square.and.arrow.down.fill"
        case .trash:
            return "trash.fill"
        case .other:
            return "tray.full.fill"
        }
    }

    var rationale: String {
        switch self {
        case .buildArtifacts:
            return "Generated build output that can usually be recreated on demand."
        case .applicationBuilds:
            return "Packaged application artifacts such as installers, bundles, and release binaries."
        case .devCaches:
            return "Dependency caches and toolchain state that often balloon over time."
        case .largeFiles:
            return "Heavy items that dominate disk usage and deserve manual review."
        case .oldFiles:
            return "Dormant files that have not been touched in months."
        case .logs:
            return "Diagnostic output and stale logs."
        case .downloadsInstallers:
            return "Installers, archives, and downloads that are often no longer needed."
        case .trash:
            return "Items already marked for deletion by the user."
        case .other:
            return "Additional clutter detected with lower confidence."
        }
    }
}

enum ScanRisk: String, Codable, Sendable {
    case low
    case medium
    case high

    var title: String {
        rawValue.capitalized
    }
}

enum ScanRecommendation: String, Codable, Sendable {
    case recommended
    case review
    case manualInspection

    var title: String {
        switch self {
        case .recommended:
            return "Recommended"
        case .review:
            return "Review"
        case .manualInspection:
            return "Manual Inspection"
        }
    }
}

enum ScanItemKind: String, Codable, Sendable {
    case file
    case directory
    case package
}

enum ScanItemSizing: String, Codable, Sendable {
    case exact
    case estimatedFastFolder

    var title: String {
        switch self {
        case .exact:
            return "Exact"
        case .estimatedFastFolder:
            return "Estimated Fast Folder"
        }
    }
}

struct ScanItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let path: String
    let kind: ScanItemKind
    let byteSize: Int64
    let lastUsedDate: Date?
    let modifiedDate: Date?
    let toolchain: String?
    let category: ScanCategory
    let risk: ScanRisk
    let recommendation: ScanRecommendation
    let reason: String
    let sizing: ScanItemSizing
    let capturedChildCount: Int?

    init(
        id: String,
        path: String,
        kind: ScanItemKind,
        byteSize: Int64,
        lastUsedDate: Date?,
        modifiedDate: Date?,
        toolchain: String?,
        category: ScanCategory,
        risk: ScanRisk,
        recommendation: ScanRecommendation,
        reason: String,
        sizing: ScanItemSizing = .exact,
        capturedChildCount: Int? = nil
    ) {
        self.id = id
        self.path = path
        self.kind = kind
        self.byteSize = byteSize
        self.lastUsedDate = lastUsedDate
        self.modifiedDate = modifiedDate
        self.toolchain = toolchain
        self.category = category
        self.risk = risk
        self.recommendation = recommendation
        self.reason = reason
        self.sizing = sizing
        self.capturedChildCount = capturedChildCount
    }

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var folderPath: String {
        url.deletingLastPathComponent().path
    }

    var updatedAt: Date? {
        modifiedDate ?? lastUsedDate
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var isDirectory: Bool {
        kind != .file
    }

    var sizeDisplayString: String {
        switch sizing {
        case .exact:
            return byteSize.byteString
        case .estimatedFastFolder:
            return "Est. \(byteSize.byteString)"
        }
    }

    var scanCaptureDescription: String {
        switch sizing {
        case .exact:
            return "Exact size"
        case .estimatedFastFolder:
            if let capturedChildCount {
                return "Fast folder estimate from \(capturedChildCount.formatted()) top-level entries"
            }
            return "Fast folder estimate"
        }
    }
}

struct CategorySummary: Codable, Hashable, Sendable {
    let category: ScanCategory
    let itemCount: Int
    let totalBytes: Int64
    let reclaimableBytes: Int64
    let recommendedBytes: Int64
    let highestRisk: ScanRisk
}

enum ScanPhase: String, Codable, Sendable {
    case preparing
    case inventory
    case detection
    case aggregation
    case completed
}

struct ScanProgress: Codable, Hashable, Sendable {
    let phase: ScanPhase
    let processedEntries: Int
    let matchedItems: Int
    let currentPath: String?
    let currentCategory: ScanCategory?
}

struct ScanSnapshot: Codable, Hashable, Sendable {
    let target: ScanTarget
    let itemCount: Int
    let summaries: [CategorySummary]
    let startedAt: Date
    let endedAt: Date
    let totalMatchedBytes: Int64
}

enum ScanEvent: Sendable {
    case started(ScanTarget)
    case progress(ScanProgress)
    case item(ScanItem)
    case completed(ScanSnapshot)
    case failed(String)
    case cancelled
}


