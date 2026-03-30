import AppKit
import Foundation

protocol PermissionProviding {
    func snapshot() -> PermissionSnapshot
    func openSystemSettings(for requirement: PermissionRequirement)
}

struct PermissionCenter: PermissionProviding {
    private let fileManager = FileManager.default

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(statuses: PermissionRequirement.allCases.map(makeStatus(for:)))
    }

    func openSystemSettings(for requirement: PermissionRequirement) {
        let urls: [URL?] = {
            switch requirement {
            case .fullDiskAccess:
                return [
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
                    URL(string: "x-apple.systempreferences:"),
                ]
            case .downloadsFolder:
                return [
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"),
                    URL(string: "x-apple.systempreferences:"),
                ]
            case .desktopFolder:
                return [
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"),
                    URL(string: "x-apple.systempreferences:"),
                ]
            }
        }()

        for url in urls.compactMap({ $0 }) {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"), configuration: .init())
    }

    private func makeStatus(for requirement: PermissionRequirement) -> PermissionStatus {
        let state: PermissionState
        let details: String

        switch requirement {
        case .fullDiskAccess:
            state = fullDiskAccessState()
            details = switch state {
            case .granted:
                "Protected locations can be inspected."
            case .unknown:
                "Protected locations were not detected on this Mac yet."
            case .denied, .needsManualSetup:
                "Open System Settings > Privacy & Security > Full Disk Access and enable this app."
            }

        case .downloadsFolder:
            state = readableFolderState(at: fileManager.homeDirectoryForCurrentUser.appending(path: "Downloads"))
            details = state == .granted
                ? "Downloads can be scanned for installers and archives."
                : "Downloads visibility is limited until access is granted."

        case .desktopFolder:
            state = readableFolderState(at: fileManager.homeDirectoryForCurrentUser.appending(path: "Desktop"))
            details = state == .granted
                ? "Desktop can be scanned for large project files."
                : "Desktop visibility is limited until access is granted."
        }

        return PermissionStatus(
            requirement: requirement,
            state: state,
            details: details,
            lastCheckedAt: .now
        )
    }

    private func fullDiskAccessState() -> PermissionState {
        let protectedCandidates = [
            fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Mail"),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Messages"),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Safari"),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC"),
        ]

        var foundProtectedLocation = false
        for candidate in protectedCandidates where fileManager.fileExists(atPath: candidate.path) {
            foundProtectedLocation = true
            do {
                _ = try fileManager.contentsOfDirectory(at: candidate, includingPropertiesForKeys: nil)
                return .granted
            } catch {
                continue
            }
        }

        return foundProtectedLocation ? .needsManualSetup : .unknown
    }

    private func readableFolderState(at url: URL) -> PermissionState {
        guard fileManager.fileExists(atPath: url.path) else {
            return .unknown
        }

        do {
            _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return .granted
        } catch {
            return .needsManualSetup
        }
    }
}
