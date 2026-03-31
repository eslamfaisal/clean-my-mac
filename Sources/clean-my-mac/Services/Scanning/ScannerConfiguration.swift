import Foundation

struct ScannerConfiguration: Sendable {
    let largeFileThresholdBytes: Int64
    let oldFileCutoff: Date
    let protectedSystemPrefixes: [String]
    let excludedDatabasePaths: [String]

    /// Pre-compiled regex cache for glob pattern matching.
    /// Built once per scan session to avoid per-file regex compilation.
    private let compiledGlobCache: GlobCache

    static func `default`(databasePath: String? = nil) -> ScannerConfiguration {
        var dbPaths: [String] = []
        if let databasePath {
            dbPaths.append(databasePath)
            // Also exclude WAL and SHM companion files
            dbPaths.append(databasePath + "-wal")
            dbPaths.append(databasePath + "-shm")
        }

        return ScannerConfiguration(
            largeFileThresholdBytes: 512 * 1_024 * 1_024,
            oldFileCutoff: Calendar.current.date(byAdding: .day, value: -180, to: .now) ?? .distantPast,
            protectedSystemPrefixes: [
                "/System",
                "/dev",
                "/proc",
                "/sbin",
                "/usr/sbin",
                "/private/var/vm",
                "/private/var/db",
                "/private/var/folders",
                "/private/var/tmp",
                "/private/preboot",
                "/cores",
                "/Network",
                "/Applications",
                "/Library/Apple",
                "/Library/Extensions",
                "/Library/Frameworks",
                "/Library/Filesystems",
            ],
            excludedDatabasePaths: dbPaths,
            compiledGlobCache: GlobCache()
        )
    }

    func shouldSkipTraversal(at url: URL, isDirectory: Bool, rules: [UserRule]) -> Bool {
        let standardizedPath = url.standardizedFileURL.path

        // Skip our own SQLite database files
        if excludedDatabasePaths.contains(standardizedPath) {
            return true
        }

        if protectedSystemPrefixes.contains(where: { standardizedPath == $0 || standardizedPath.hasPrefix("\($0)/") }) {
            return true
        }

        if standardizedPath.hasPrefix("/Volumes/") && standardizedPath != "/" {
            return true
        }

        for rule in rules {
            switch rule.kind {
            case .excludedPath:
                let excluded = URL(fileURLWithPath: rule.value).standardizedFileURL.path
                if standardizedPath == excluded || standardizedPath.hasPrefix("\(excluded)/") {
                    return true
                }

            case .excludedPattern:
                if compiledGlobCache.matches(pattern: rule.value, in: standardizedPath) {
                    return true
                }

            case .categoryPreference:
                continue
            }
        }

        if isDirectory, [".Trash-1000"].contains(url.lastPathComponent) {
            return true
        }

        return false
    }

    func categoryIsDisabled(_ category: ScanCategory, rules: [UserRule]) -> Bool {
        rules.contains(where: { $0.kind == .categoryPreference && $0.category == category && $0.value == "disabled" })
    }
}

// MARK: - Compiled Glob Cache

/// Thread-safe cache that compiles glob patterns into NSRegularExpression instances once,
/// then reuses them for all subsequent matches. Eliminates per-file regex compilation overhead.
final class GlobCache: @unchecked Sendable {
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func matches(pattern: String, in path: String) -> Bool {
        let regex: NSRegularExpression? = lock.withLock {
            if let cached = cache[pattern] {
                return cached
            }
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
            let compiled = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive])
            if let compiled {
                cache[pattern] = compiled
            }
            return compiled
        }

        guard let regex else { return false }
        let range = NSRange(location: 0, length: path.utf16.count)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }
}
