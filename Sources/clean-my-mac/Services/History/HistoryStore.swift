import Foundation

actor HistoryStore {
    struct PersistedState: Codable, Sendable {
        var rules: [UserRule]
        var entries: [ScanHistoryEntry]
    }

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let stateURL: URL

    init(folderName: String = "CleanMyMac") {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: folderName, directoryHint: .isDirectory)
        self.stateURL = baseURL.appending(path: "history-state.json")
    }

    func load() -> PersistedState {
        do {
            let data = try Data(contentsOf: stateURL)
            return try decoder.decode(PersistedState.self, from: data)
        } catch {
            return PersistedState(rules: [], entries: [])
        }
    }

    func save(rules: [UserRule], entries: [ScanHistoryEntry]) async {
        let state = PersistedState(rules: rules, entries: entries)
        try? persist(state)
    }

    func append(entry: ScanHistoryEntry, existingRules: [UserRule], existingEntries: [ScanHistoryEntry]) async -> [ScanHistoryEntry] {
        let updatedEntries = ([entry] + existingEntries).sorted { $0.scannedAt > $1.scannedAt }
        let state = PersistedState(rules: existingRules, entries: updatedEntries)
        try? persist(state)
        return updatedEntries
    }

    private func persist(_ state: PersistedState) throws {
        let directory = stateURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }
}
