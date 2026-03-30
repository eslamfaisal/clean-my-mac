import Foundation

protocol ScanStreaming {
    func scan(target: ScanTarget, rules: [UserRule]) -> AsyncThrowingStream<ScanEvent, Error>
}

struct FileSystemScanner: ScanStreaming, Sendable {
    private let configuration: ScannerConfiguration
    private let classifier: ScanClassifier

    init(configuration: ScannerConfiguration = .default()) {
        self.configuration = configuration
        self.classifier = ScanClassifier(configuration: configuration)
    }

    func scan(target: ScanTarget, rules: [UserRule]) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [configuration, classifier] in
                do {
                    continuation.yield(.started(target))
                    let snapshot = try Self.performScan(
                        target: target,
                        rules: rules,
                        continuation: continuation,
                        configuration: configuration,
                        classifier: classifier
                    )
                    continuation.yield(.completed(snapshot))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func performScan(
        target: ScanTarget,
        rules: [UserRule],
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation,
        configuration: ScannerConfiguration,
        classifier: ScanClassifier
    ) throws -> ScanSnapshot {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .creationDateKey,
        ]

        let startedAt = Date()
        var itemsByPath: [String: ScanItem] = [:]
        var processedEntries = 0
        var matchedItems = 0

        continuation.yield(.progress(ScanProgress(
            phase: .inventory,
            processedEntries: processedEntries,
            matchedItems: matchedItems,
            currentPath: nil,
            currentCategory: nil
        )))

        for rootURL in target.rootURLs {
            try Task.checkCancellation()

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()

                let values = try? url.resourceValues(forKeys: keys)
                let isDirectory = values?.isDirectory ?? false

                if configuration.shouldSkipTraversal(at: url, isDirectory: isDirectory, rules: rules) {
                    if isDirectory {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                processedEntries += 1
                if processedEntries % 300 == 0 {
                    continuation.yield(.progress(ScanProgress(
                        phase: .detection,
                        processedEntries: processedEntries,
                        matchedItems: matchedItems,
                        currentPath: url.path,
                        currentCategory: nil
                    )))
                }

                if isDirectory {
                    if let decision = classifier.classifyDirectory(at: url, rules: rules) {
                        let size = try directorySize(at: url, fileManager: fileManager)
                        guard size > 0 else {
                            enumerator.skipDescendants()
                            continue
                        }

                        let kind: ScanItemKind = (values?.isPackage ?? false) ? .package : .directory
                        let item = ScanItem(
                            id: url.standardizedFileURL.path,
                            path: url.standardizedFileURL.path,
                            kind: kind,
                            byteSize: size,
                            lastUsedDate: values?.contentAccessDate,
                            modifiedDate: values?.contentModificationDate,
                            toolchain: decision.toolchain,
                            category: decision.category,
                            risk: decision.risk,
                            recommendation: decision.recommendation,
                            reason: decision.reason
                        )

                        if itemsByPath[item.path] == nil {
                            itemsByPath[item.path] = item
                            matchedItems += 1
                            continuation.yield(.item(item))
                        }

                        if decision.captureDirectory {
                            continuation.yield(.progress(ScanProgress(
                                phase: .detection,
                                processedEntries: processedEntries,
                                matchedItems: matchedItems,
                                currentPath: url.path,
                                currentCategory: decision.category
                            )))
                            enumerator.skipDescendants()
                        }
                    }
                    continue
                }

                let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
                guard size > 0 else { continue }

                if let decision = classifier.classifyFile(at: url, size: size, modifiedAt: values?.contentModificationDate ?? values?.creationDate, rules: rules) {
                    let item = ScanItem(
                        id: url.standardizedFileURL.path,
                        path: url.standardizedFileURL.path,
                        kind: .file,
                        byteSize: size,
                        lastUsedDate: values?.contentAccessDate,
                        modifiedDate: values?.contentModificationDate ?? values?.creationDate,
                        toolchain: decision.toolchain,
                        category: decision.category,
                        risk: decision.risk,
                        recommendation: decision.recommendation,
                        reason: decision.reason
                    )

                    if itemsByPath[item.path] == nil {
                        itemsByPath[item.path] = item
                        matchedItems += 1
                        continuation.yield(.item(item))
                    }
                }
            }
        }

        continuation.yield(.progress(ScanProgress(
            phase: .aggregation,
            processedEntries: processedEntries,
            matchedItems: matchedItems,
            currentPath: nil,
            currentCategory: nil
        )))

        let items = itemsByPath.values.sorted { lhs, rhs in
            if lhs.byteSize == rhs.byteSize {
                return lhs.path < rhs.path
            }
            return lhs.byteSize > rhs.byteSize
        }
        let summaries = items.summaries()
        let total = items.reduce(into: Int64.zero) { $0 += $1.byteSize }

        return ScanSnapshot(
            target: target,
            items: items,
            summaries: summaries,
            startedAt: startedAt,
            endedAt: .now,
            totalMatchedBytes: total
        )
    }

    private static func directorySize(at url: URL, fileManager: FileManager) throws -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        while let nestedURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try? nestedURL.resourceValues(forKeys: resourceKeys)
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
