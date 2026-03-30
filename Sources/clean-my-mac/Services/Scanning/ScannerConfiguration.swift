import Foundation

struct ScannerConfiguration: Sendable {
    let largeFileThresholdBytes: Int64
    let oldFileCutoff: Date
    let protectedSystemPrefixes: [String]

    static func `default`() -> ScannerConfiguration {
        ScannerConfiguration(
            largeFileThresholdBytes: 512 * 1_024 * 1_024,
            oldFileCutoff: Calendar.current.date(byAdding: .day, value: -180, to: .now) ?? .distantPast,
            protectedSystemPrefixes: [
                "/System",
                "/dev",
                "/proc",
                "/private/var/vm",
                "/private/preboot",
                "/cores",
                "/Network",
            ]
        )
    }

    func shouldSkipTraversal(at url: URL, isDirectory: Bool, rules: [UserRule]) -> Bool {
        let standardizedPath = url.standardizedFileURL.path

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
                if globMatch(pattern: rule.value, in: standardizedPath) {
                    return true
                }

            case .categoryPreference:
                continue
            }
        }

        if isDirectory, [".git", ".Trash-1000"].contains(url.lastPathComponent) {
            return true
        }

        return false
    }

    func categoryIsDisabled(_ category: ScanCategory, rules: [UserRule]) -> Bool {
        rules.contains(where: { $0.kind == .categoryPreference && $0.category == category && $0.value == "disabled" })
    }

    private func globMatch(pattern: String, in path: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        let regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive])
        let range = NSRange(location: 0, length: path.utf16.count)
        return regex?.firstMatch(in: path, options: [], range: range) != nil
    }
}
