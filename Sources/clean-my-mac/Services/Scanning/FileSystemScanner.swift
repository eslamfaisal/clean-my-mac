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

    private struct DirectoryMetrics {
        let byteSize: Int64
        let sizing: ScanItemSizing
        let childCount: Int?
    }

    private struct FolderEstimatePolicy {
        let minimumBytes: Int64
        let averageBytesPerEntry: Int64
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
            .directoryEntryCountKey,
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
                        let metrics = try directoryMetrics(
                            at: url,
                            values: values,
                            fileManager: fileManager,
                            decision: decision
                        )
                        guard metrics.byteSize > 0 else {
                            enumerator.skipDescendants()
                            continue
                        }

                        let kind: ScanItemKind = (values?.isPackage ?? false) ? .package : .directory
                        let item = ScanItem(
                            id: url.standardizedFileURL.path,
                            path: url.standardizedFileURL.path,
                            kind: kind,
                            byteSize: metrics.byteSize,
                            lastUsedDate: values?.contentAccessDate,
                            modifiedDate: values?.contentModificationDate,
                            toolchain: decision.toolchain,
                            category: decision.category,
                            risk: decision.risk,
                            recommendation: decision.recommendation,
                            reason: decision.reason,
                            sizing: metrics.sizing,
                            capturedChildCount: metrics.childCount
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

                let size = fileByteSize(at: url, values: values, fileManager: fileManager)
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
            total += fileByteSize(at: nestedURL, values: values, fileManager: fileManager)
        }
        return total
    }

    private static func directoryMetrics(
        at url: URL,
        values: URLResourceValues?,
        fileManager: FileManager,
        decision: ClassificationDecision
    ) throws -> DirectoryMetrics {
        switch decision.directorySizing {
        case .recursiveExact:
            let size = try directorySize(at: url, fileManager: fileManager)
            return DirectoryMetrics(
                byteSize: size,
                sizing: .exact,
                childCount: values?.directoryEntryCount
            )

        case .estimatedFastFolder:
            return try fastDirectoryEstimate(
                at: url,
                values: values,
                fileManager: fileManager,
                decision: decision
            )
        }
    }

    private static func fastDirectoryEstimate(
        at url: URL,
        values: URLResourceValues?,
        fileManager: FileManager,
        decision: ClassificationDecision
    ) throws -> DirectoryMetrics {
        try Task.checkCancellation()

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
        ]

        let childURLs = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )) ?? []

        var directFileBytes: Int64 = 0
        for childURL in childURLs {
            try Task.checkCancellation()
            let childValues = try? childURL.resourceValues(forKeys: resourceKeys)
            guard childValues?.isRegularFile == true else { continue }
            directFileBytes += fileByteSize(at: childURL, values: childValues, fileManager: fileManager)
        }

        let childCount = values?.directoryEntryCount ?? childURLs.count
        let policy = folderEstimatePolicy(for: url, decision: decision)
        var estimatedBytes = directFileBytes

        if childCount > 0 {
            estimatedBytes = max(estimatedBytes, Int64(childCount) * policy.averageBytesPerEntry)
            estimatedBytes = max(estimatedBytes, policy.minimumBytes)
        }

        return DirectoryMetrics(
            byteSize: estimatedBytes,
            sizing: .estimatedFastFolder,
            childCount: childCount > 0 ? childCount : nil
        )
    }

    private static func folderEstimatePolicy(for url: URL, decision: ClassificationDecision) -> FolderEstimatePolicy {
        let name = url.lastPathComponent.lowercased()
        let path = url.standardizedFileURL.path.lowercased()

        if name == "node_modules" {
            return FolderEstimatePolicy(minimumBytes: 256 * 1_024 * 1_024, averageBytesPerEntry: 2 * 1_024 * 1_024)
        }

        if name == "deriveddata" || path.contains("/library/developer/xcode/deriveddata") {
            return FolderEstimatePolicy(minimumBytes: 768 * 1_024 * 1_024, averageBytesPerEntry: 48 * 1_024 * 1_024)
        }

        if [".gradle", ".dart_tool", ".pub-cache", ".pnpm-store", ".npm", ".yarn", ".terraform", ".terragrunt-cache", ".turbo", ".parcel-cache", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".nox"].contains(name) {
            return FolderEstimatePolicy(minimumBytes: 96 * 1_024 * 1_024, averageBytesPerEntry: 8 * 1_024 * 1_024)
        }

        if [".build", "build", "dist", "out", "release", "debug", "target", "flutter_build", "intermediates", ".cxx", ".next", ".nuxt", ".svelte-kit", ".output", "storybook-static", "bazel-out", "bazel-bin", "bazel-testlogs", "cmakefiles"].contains(name) || name.hasPrefix("cmake-build-") {
            return FolderEstimatePolicy(minimumBytes: 192 * 1_024 * 1_024, averageBytesPerEntry: 24 * 1_024 * 1_024)
        }

        if name == "pods" {
            return FolderEstimatePolicy(minimumBytes: 160 * 1_024 * 1_024, averageBytesPerEntry: 6 * 1_024 * 1_024)
        }

        if name == ".venv" || name == "venv" {
            return FolderEstimatePolicy(minimumBytes: 128 * 1_024 * 1_024, averageBytesPerEntry: 10 * 1_024 * 1_024)
        }

        switch decision.category {
        case .buildArtifacts:
            return FolderEstimatePolicy(minimumBytes: 128 * 1_024 * 1_024, averageBytesPerEntry: 16 * 1_024 * 1_024)
        case .devCaches:
            return FolderEstimatePolicy(minimumBytes: 64 * 1_024 * 1_024, averageBytesPerEntry: 8 * 1_024 * 1_024)
        default:
            return FolderEstimatePolicy(minimumBytes: 16 * 1_024 * 1_024, averageBytesPerEntry: 1 * 1_024 * 1_024)
        }
    }

    private static func fileByteSize(at url: URL, values: URLResourceValues?, fileManager: FileManager) -> Int64 {
        let resourceValueSize = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        if resourceValueSize > 0 {
            return resourceValueSize
        }

        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return Int64((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
    }
}
