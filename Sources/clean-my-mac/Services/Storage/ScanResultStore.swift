import Foundation
import SQLite3

// MARK: - Protocol

protocol ScanResultStoring: Sendable {
    func resetForNewScan() throws
    func insertBatch(_ items: [ScanItem]) throws
    func fetchPage(
        category: ScanCategory?,
        searchText: String?,
        offset: Int,
        limit: Int
    ) -> [ScanItem]
    func totalCount(category: ScanCategory?, searchText: String?) -> Int
    func categorySummaries() -> [CategorySummary]
    func topOffenders(limit: Int) -> [ScanItem]
    func totalMatchedBytes() -> Int64
    func itemCount() -> Int
    func fetchItems(ids: Set<String>) -> [ScanItem]
    func deleteItems(paths: Set<String>) throws
    func deleteItemsMatching(excludedPath: String) throws
    func selectedReclaimableBytes(ids: Set<String>) -> Int64
    func recommendedItemCount() -> Int
    var databasePath: String { get }
}

// MARK: - Implementation

final class ScanResultStore: ScanResultStoring, @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.cleanmymac.scanresultstore", qos: .userInitiated)
    let databasePath: String

    init(folderName: String = "CleanMyMac") {
        let fm = FileManager.default
        let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let baseURL = appSupportURL.appending(path: folderName, directoryHint: .isDirectory)
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        self.databasePath = baseURL.appending(path: "scan_results.sqlite").path

        queue.sync {
            openDatabase()
            createTable()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    func resetForNewScan() throws {
        try queue.sync {
            try execute("DROP TABLE IF EXISTS scan_items")
            try execute("DROP TABLE IF EXISTS scan_meta")
            createTable()
        }
    }

    func insertBatch(_ items: [ScanItem]) throws {
        guard !items.isEmpty else { return }
        try queue.sync {
            try execute("BEGIN TRANSACTION")
            defer { try? execute("COMMIT") }

            let sql = """
                INSERT OR IGNORE INTO scan_items (
                    path, kind, byte_size, last_used_date, modified_date,
                    toolchain, category, risk, recommendation, reason,
                    sizing, captured_child_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw StoreError.prepareFailed(msg)
            }
            defer { sqlite3_finalize(stmt) }

            for item in items {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                bindText(stmt, 1, item.path)
                bindText(stmt, 2, item.kind.rawValue)
                sqlite3_bind_int64(stmt, 3, item.byteSize)
                bindOptionalDouble(stmt, 4, item.lastUsedDate?.timeIntervalSince1970)
                bindOptionalDouble(stmt, 5, item.modifiedDate?.timeIntervalSince1970)
                bindOptionalText(stmt, 6, item.toolchain)
                bindText(stmt, 7, item.category.rawValue)
                bindText(stmt, 8, item.risk.rawValue)
                bindText(stmt, 9, item.recommendation.rawValue)
                bindText(stmt, 10, item.reason)
                bindText(stmt, 11, item.sizing.rawValue)
                if let childCount = item.capturedChildCount {
                    sqlite3_bind_int(stmt, 12, Int32(childCount))
                } else {
                    sqlite3_bind_null(stmt, 12)
                }

                let result = sqlite3_step(stmt)
                if result != SQLITE_DONE && result != SQLITE_CONSTRAINT {
                    let msg = String(cString: sqlite3_errmsg(db))
                    try? execute("ROLLBACK")
                    throw StoreError.insertFailed(msg)
                }
            }
        }
    }

    func fetchPage(
        category: ScanCategory?,
        searchText: String?,
        offset: Int,
        limit: Int
    ) -> [ScanItem] {
        queue.sync {
            var conditions: [String] = []
            var bindings: [(Int32, String)] = []
            var bindIndex: Int32 = 1

            if let category {
                conditions.append("category = ?")
                bindings.append((bindIndex, category.rawValue))
                bindIndex += 1
            }

            if let searchText, !searchText.isEmpty {
                conditions.append("path LIKE ?")
                bindings.append((bindIndex, "%\(searchText)%"))
                bindIndex += 1
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = """
                SELECT * FROM scan_items
                \(whereClause)
                ORDER BY byte_size DESC, path ASC
                LIMIT ? OFFSET ?
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            for (idx, value) in bindings {
                bindText(stmt, idx, value)
            }
            sqlite3_bind_int(stmt, bindIndex, Int32(limit))
            sqlite3_bind_int(stmt, bindIndex + 1, Int32(offset))

            var results: [ScanItem] = []
            results.reserveCapacity(limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = readScanItem(from: stmt) {
                    results.append(item)
                }
            }
            return results
        }
    }

    func totalCount(category: ScanCategory?, searchText: String?) -> Int {
        queue.sync {
            var conditions: [String] = []
            var bindings: [(Int32, String)] = []
            var bindIndex: Int32 = 1

            if let category {
                conditions.append("category = ?")
                bindings.append((bindIndex, category.rawValue))
                bindIndex += 1
            }

            if let searchText, !searchText.isEmpty {
                conditions.append("path LIKE ?")
                bindings.append((bindIndex, "%\(searchText)%"))
                bindIndex += 1
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = "SELECT COUNT(*) FROM scan_items \(whereClause)"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }

            for (idx, value) in bindings {
                bindText(stmt, idx, value)
            }

            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }
    }

    func categorySummaries() -> [CategorySummary] {
        queue.sync {
            let sql = """
                SELECT
                    category,
                    COUNT(*) as item_count,
                    SUM(byte_size) as total_bytes,
                    SUM(CASE WHEN recommendation = 'recommended' THEN byte_size ELSE 0 END) as recommended_bytes,
                    MAX(CASE risk
                        WHEN 'high' THEN 2
                        WHEN 'medium' THEN 1
                        ELSE 0
                    END) as max_risk
                FROM scan_items
                GROUP BY category
                ORDER BY total_bytes DESC
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var results: [CategorySummary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let categoryRaw = columnText(stmt, 0),
                      let category = ScanCategory(rawValue: categoryRaw) else { continue }

                let itemCount = Int(sqlite3_column_int(stmt, 1))
                let totalBytes = sqlite3_column_int64(stmt, 2)
                let recommendedBytes = sqlite3_column_int64(stmt, 3)
                let maxRiskInt = Int(sqlite3_column_int(stmt, 4))
                let highestRisk: ScanRisk = switch maxRiskInt {
                case 2: .high
                case 1: .medium
                default: .low
                }

                results.append(CategorySummary(
                    category: category,
                    itemCount: itemCount,
                    totalBytes: totalBytes,
                    reclaimableBytes: totalBytes,
                    recommendedBytes: recommendedBytes,
                    highestRisk: highestRisk
                ))
            }
            return results
        }
    }

    func topOffenders(limit: Int) -> [ScanItem] {
        fetchPage(category: nil, searchText: nil, offset: 0, limit: limit)
    }

    func totalMatchedBytes() -> Int64 {
        queue.sync {
            querySingleInt64("SELECT COALESCE(SUM(byte_size), 0) FROM scan_items")
        }
    }

    func itemCount() -> Int {
        queue.sync {
            Int(querySingleInt64("SELECT COUNT(*) FROM scan_items"))
        }
    }

    func fetchItems(ids: Set<String>) -> [ScanItem] {
        guard !ids.isEmpty else { return [] }
        return queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "SELECT * FROM scan_items WHERE path IN (\(placeholders)) ORDER BY byte_size DESC"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            for id in ids {
                bindText(stmt, idx, id)
                idx += 1
            }

            var results: [ScanItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = readScanItem(from: stmt) {
                    results.append(item)
                }
            }
            return results
        }
    }

    func deleteItems(paths: Set<String>) throws {
        guard !paths.isEmpty else { return }
        try queue.sync {
            try execute("BEGIN TRANSACTION")
            defer { try? execute("COMMIT") }

            let placeholders = paths.map { _ in "?" }.joined(separator: ", ")
            let sql = "DELETE FROM scan_items WHERE path IN (\(placeholders))"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                try? execute("ROLLBACK")
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            for path in paths {
                bindText(stmt, idx, path)
                idx += 1
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                try? execute("ROLLBACK")
                throw StoreError.deleteFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func deleteItemsMatching(excludedPath: String) throws {
        try queue.sync {
            let sql = "DELETE FROM scan_items WHERE path = ? OR path LIKE ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            let normalized = URL(fileURLWithPath: excludedPath).standardizedFileURL.path
            bindText(stmt, 1, normalized)
            bindText(stmt, 2, normalized + "/%")

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw StoreError.deleteFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func selectedReclaimableBytes(ids: Set<String>) -> Int64 {
        guard !ids.isEmpty else { return 0 }
        return queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "SELECT COALESCE(SUM(byte_size), 0) FROM scan_items WHERE path IN (\(placeholders))"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            for id in ids {
                bindText(stmt, idx, id)
                idx += 1
            }

            return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
        }
    }

    func recommendedItemCount() -> Int {
        queue.sync {
            Int(querySingleInt64("SELECT COUNT(*) FROM scan_items WHERE recommendation = 'recommended'"))
        }
    }

    // MARK: - Private Helpers

    private func openDatabase() {
        guard sqlite3_open(databasePath, &db) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            fatalError("ScanResultStore: Failed to open database at \(databasePath): \(msg)")
        }

        // Performance pragmas for scan workload
        try? execute("PRAGMA journal_mode = WAL")
        try? execute("PRAGMA synchronous = NORMAL")
        try? execute("PRAGMA cache_size = -8000")       // 8 MB page cache
        try? execute("PRAGMA temp_store = MEMORY")
        try? execute("PRAGMA mmap_size = 67108864")      // 64 MB mmap
    }

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS scan_items (
                path TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                byte_size INTEGER NOT NULL,
                last_used_date REAL,
                modified_date REAL,
                toolchain TEXT,
                category TEXT NOT NULL,
                risk TEXT NOT NULL,
                recommendation TEXT NOT NULL,
                reason TEXT NOT NULL,
                sizing TEXT NOT NULL,
                captured_child_count INTEGER
            )
            """

        try? execute(sql)
        try? execute("CREATE INDEX IF NOT EXISTS idx_scan_items_category ON scan_items(category)")
        try? execute("CREATE INDEX IF NOT EXISTS idx_scan_items_byte_size ON scan_items(byte_size DESC)")
        try? execute("CREATE INDEX IF NOT EXISTS idx_scan_items_cat_size ON scan_items(category, byte_size DESC)")
        try? execute("CREATE INDEX IF NOT EXISTS idx_scan_items_recommendation ON scan_items(recommendation)")
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let msg = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw StoreError.executionFailed(msg)
        }
    }

    private func querySingleInt64(_ sql: String) -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    private func readScanItem(from stmt: OpaquePointer?) -> ScanItem? {
        guard let path = columnText(stmt, 0),
              let kindRaw = columnText(stmt, 1),
              let kind = ScanItemKind(rawValue: kindRaw),
              let categoryRaw = columnText(stmt, 6),
              let category = ScanCategory(rawValue: categoryRaw),
              let riskRaw = columnText(stmt, 7),
              let risk = ScanRisk(rawValue: riskRaw),
              let recommendationRaw = columnText(stmt, 8),
              let recommendation = ScanRecommendation(rawValue: recommendationRaw),
              let reason = columnText(stmt, 9),
              let sizingRaw = columnText(stmt, 10),
              let sizing = ScanItemSizing(rawValue: sizingRaw) else {
            return nil
        }

        let byteSize = sqlite3_column_int64(stmt, 2)
        let lastUsedDate = columnOptionalDate(stmt, 3)
        let modifiedDate = columnOptionalDate(stmt, 4)
        let toolchain = columnText(stmt, 5)
        let capturedChildCountRaw = sqlite3_column_type(stmt, 11) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int(stmt, 11))

        return ScanItem(
            id: path,
            path: path,
            kind: kind,
            byteSize: byteSize,
            lastUsedDate: lastUsedDate,
            modifiedDate: modifiedDate,
            toolchain: toolchain,
            category: category,
            risk: risk,
            recommendation: recommendation,
            reason: reason,
            sizing: sizing,
            capturedChildCount: capturedChildCountRaw
        )
    }

    // MARK: - SQLite Binding Helpers

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            bindText(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func columnOptionalDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    // MARK: - Error Types

    enum StoreError: Error, LocalizedError {
        case prepareFailed(String)
        case insertFailed(String)
        case deleteFailed(String)
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .prepareFailed(let msg): "SQLite prepare failed: \(msg)"
            case .insertFailed(let msg): "SQLite insert failed: \(msg)"
            case .deleteFailed(let msg): "SQLite delete failed: \(msg)"
            case .executionFailed(let msg): "SQLite execution failed: \(msg)"
            }
        }
    }
}
