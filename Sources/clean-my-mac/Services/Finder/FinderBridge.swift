import AppKit
import Foundation

protocol FinderBridging {
    func reveal(path: String)
    func openFolder(path: String)
    func open(path: String)
}

struct FinderBridge: FinderBridging {
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
