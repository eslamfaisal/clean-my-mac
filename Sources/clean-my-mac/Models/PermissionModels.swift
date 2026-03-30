import Foundation

enum PermissionRequirement: String, CaseIterable, Codable, Identifiable, Sendable {
    case fullDiskAccess
    case downloadsFolder
    case desktopFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullDiskAccess:
            return "Full Disk Access"
        case .downloadsFolder:
            return "Downloads Visibility"
        case .desktopFolder:
            return "Desktop Visibility"
        }
    }

    var summary: String {
        switch self {
        case .fullDiskAccess:
            return "Needed to inspect protected caches, logs, and developer artifacts across the disk."
        case .downloadsFolder:
            return "Used to classify installers, archives, and stale downloads."
        case .desktopFolder:
            return "Used to surface large files and project artifacts left on the Desktop."
        }
    }

    var isOptional: Bool {
        switch self {
        case .fullDiskAccess:
            return false
        case .downloadsFolder, .desktopFolder:
            return true
        }
    }
}

enum PermissionState: String, Codable, Sendable {
    case unknown
    case granted
    case denied
    case needsManualSetup

    var statusLabel: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .needsManualSetup:
            return "Needs Setup"
        }
    }
}

struct PermissionStatus: Codable, Identifiable, Hashable, Sendable {
    let requirement: PermissionRequirement
    var state: PermissionState
    var details: String
    var lastCheckedAt: Date

    var id: PermissionRequirement { requirement }
}

struct PermissionSnapshot: Codable, Hashable, Sendable {
    var statuses: [PermissionStatus]

    subscript(requirement: PermissionRequirement) -> PermissionStatus? {
        statuses.first(where: { $0.requirement == requirement })
    }

    var requiresAttention: Bool {
        statuses.contains(where: { !$0.requirement.isOptional && $0.state != .granted })
    }

    var missingRequirements: [PermissionStatus] {
        statuses.filter { !$0.requirement.isOptional && $0.state != .granted }
    }
}
