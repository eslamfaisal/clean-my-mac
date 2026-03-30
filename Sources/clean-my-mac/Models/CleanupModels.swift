import Foundation

enum DeleteMode: String, Codable, Sendable {
    case moveToTrash
}

struct CleanupPlan: Codable, Hashable, Sendable {
    let items: [ScanItem]
    let estimatedReclaimedBytes: Int64
    let deleteMode: DeleteMode
    let warnings: [String]
    let excludedPathsSnapshot: [String]
}

struct CleanupFailure: Codable, Hashable, Sendable, Identifiable {
    let path: String
    let reason: String

    var id: String { path }
}

struct CleanupResult: Codable, Hashable, Sendable {
    let succeededPaths: [String]
    let failedItems: [CleanupFailure]
    let reclaimedBytes: Int64
    let skippedBytes: Int64
}

enum UserRuleKind: String, Codable, Sendable {
    case excludedPath
    case excludedPattern
    case categoryPreference
}

struct UserRule: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let kind: UserRuleKind
    let value: String
    let category: ScanCategory?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: UserRuleKind,
        value: String,
        category: ScanCategory? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.category = category
        self.createdAt = createdAt
    }
}

struct ScanHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let scannedAt: Date
    let matchedBytes: Int64
    let cleanedBytes: Int64
    let itemCount: Int
    let categoryBreakdown: [String: Int64]

    init(
        id: UUID = UUID(),
        scannedAt: Date = .now,
        matchedBytes: Int64,
        cleanedBytes: Int64,
        itemCount: Int,
        categoryBreakdown: [String: Int64]
    ) {
        self.id = id
        self.scannedAt = scannedAt
        self.matchedBytes = matchedBytes
        self.cleanedBytes = cleanedBytes
        self.itemCount = itemCount
        self.categoryBreakdown = categoryBreakdown
    }
}
