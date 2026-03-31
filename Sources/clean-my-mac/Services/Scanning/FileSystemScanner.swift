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

    /// Hard cap on matched items per scan to prevent unbounded memory growth.
    static let maxMatchedItems = 50_000

    /// Memory pressure ceiling in bytes (2 GB). Scan aborts gracefully above this.
    static let memoryPressureCeiling: UInt64 = 2 * 1_024 * 1_024 * 1_024

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

        // Lightweight dedup tracker — stores only path strings, not full ScanItem objects.
        var seenPaths: Set<String> = []
        var processedEntries = 0
        var matchedItems = 0
        var totalMatchedBytes: Int64 = 0
        var lastProgressYieldAt = ProcessInfo.processInfo.systemUptime
        let progressEmissionInterval: TimeInterval = 0.16
        let progressEmissionEntryStride = 420
        var memoryCheckCounter = 0
        let memoryCheckInterval = 5_000

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

                // Memory pressure check every N entries
                memoryCheckCounter += 1
                if memoryCheckCounter % memoryCheckInterval == 0 {
                    if isMemoryPressureExceeded() {
                        continuation.yield(.failed("Scan aborted: memory pressure exceeded safe limit (\(memoryPressureCeiling / (1_024 * 1_024)) MB). Try a narrower scan scope."))
                        throw CancellationError()
                    }
                }

                // Hard cap on matched items
                if matchedItems >= maxMatchedItems {
                    continuation.yield(.progress(ScanProgress(
                        phase: .detection,
                        processedEntries: processedEntries,
                        matchedItems: matchedItems,
                        currentPath: "Item limit reached (\(maxMatchedItems))",
                        currentCategory: nil
                    )))
                    break
                }

                try autoreleasepool {
                    let values = try? url.resourceValues(forKeys: keys)
                    let isDirectory = values?.isDirectory ?? false

                    if configuration.shouldSkipTraversal(at: url, isDirectory: isDirectory, rules: rules) {
                        if isDirectory {
                            enumerator.skipDescendants()
                        }
                        return
                    }

                    processedEntries += 1
                    if processedEntries % progressEmissionEntryStride == 0,
                       shouldEmitProgress(
                        lastEmission: lastProgressYieldAt,
                        minimumInterval: progressEmissionInterval
                       ) {
                        continuation.yield(.progress(ScanProgress(
                            phase: .detection,
                            processedEntries: processedEntries,
                            matchedItems: matchedItems,
                            currentPath: url.path,
                            currentCategory: nil
                        )))
                        lastProgressYieldAt = ProcessInfo.processInfo.systemUptime
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
                                return
                            }

                            let standardizedPath = url.standardizedFileURL.path
                            let kind: ScanItemKind = (values?.isPackage ?? false) ? .package : .directory
                            let item = ScanItem(
                                id: standardizedPath,
                                path: standardizedPath,
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

                            if seenPaths.insert(standardizedPath).inserted {
                                matchedItems += 1
                                totalMatchedBytes += metrics.byteSize
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
                                lastProgressYieldAt = ProcessInfo.processInfo.systemUptime
                                enumerator.skipDescendants()
                            }
                        }
                        return
                    }

                    let size = fileByteSize(at: url, values: values, fileManager: fileManager)
                    guard size > 0 else { return }

                    if let decision = classifier.classifyFile(at: url, size: size, modifiedAt: values?.contentModificationDate ?? values?.creationDate, rules: rules) {
                        let standardizedPath = url.standardizedFileURL.path
                        let item = ScanItem(
                            id: standardizedPath,
                            path: standardizedPath,
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

                        if seenPaths.insert(standardizedPath).inserted {
                            matchedItems += 1
                            totalMatchedBytes += size
                            continuation.yield(.item(item))
                        }
                    }
                }
            }
        }

        // Release the dedup set immediately — no longer needed
        seenPaths.removeAll()

        continuation.yield(.progress(ScanProgress(
            phase: .aggregation,
            processedEntries: processedEntries,
            matchedItems: matchedItems,
            currentPath: nil,
            currentCategory: nil
        )))

        // Lightweight snapshot — no items array, just metadata.
        // Summaries will be computed from SQLite by the ViewModel.
        return ScanSnapshot(
            target: target,
            itemCount: matchedItems,
            summaries: [],
            startedAt: startedAt,
            endedAt: .now,
            totalMatchedBytes: totalMatchedBytes
        )
    }

    // MARK: - Memory Pressure

    private static func isMemoryPressureExceeded() -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return false }
        return info.resident_size > memoryPressureCeiling
    }

    // MARK: - Directory Sizing (with autoreleasepool)

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
        var batchCount = 0
        let drainInterval = 500

        while let nestedURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()

            batchCount += 1
            if batchCount % drainInterval == 0 {
                // Force autoreleasepool drain every N iterations to prevent URL/resource object accumulation
                autoreleasepool {}
            }

            autoreleasepool {
                let values = try? nestedURL.resourceValues(forKeys: resourceKeys)
                guard values?.isRegularFile == true else { return }
                total += fileByteSize(at: nestedURL, values: values, fileManager: fileManager)
            }
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
            autoreleasepool {
                let childValues = try? childURL.resourceValues(forKeys: resourceKeys)
                guard childValues?.isRegularFile == true else { return }
                directFileBytes += fileByteSize(at: childURL, values: childValues, fileManager: fileManager)
            }
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

        if ["build", "dist", "out", "release", "debug", "target", "flutter_build", "intermediates", ".cxx", ".next", ".nuxt", ".svelte-kit", ".output", "storybook-static", "bazel-out", "bazel-bin", "bazel-testlogs", "cmakefiles"].contains(name) || name.hasPrefix("cmake-build-") {
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

    private static func shouldEmitProgress(lastEmission: TimeInterval, minimumInterval: TimeInterval) -> Bool {
        ProcessInfo.processInfo.systemUptime - lastEmission >= minimumInterval
    }
}
