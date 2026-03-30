import AppKit
import Foundation

struct FinderBridge {
    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFolder(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func open(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
