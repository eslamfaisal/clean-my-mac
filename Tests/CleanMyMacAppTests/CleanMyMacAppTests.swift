import Foundation
import XCTest
@testable import CleanMyMacApp

final class CleanMyMacAppTests: XCTestCase {
    @MainActor
    func testDismissSingleItemCleanupRestoresPreviousSelection() {
        let first = ScanItem(
            id: "first",
            path: "/tmp/first.log",
            kind: .file,
            byteSize: 128,
            lastUsedDate: nil,
            modifiedDate: .now,
            toolchain: nil,
            category: .logs,
            risk: .low,
            recommendation: .recommended,
            reason: "Existing selection."
        )
        let second = ScanItem(
            id: "second",
            path: "/tmp/second.apk",
            kind: .file,
            byteSize: 256,
            lastUsedDate: nil,
            modifiedDate: .now,
            toolchain: "Android",
            category: .applicationBuilds,
            risk: .medium,
            recommendation: .review,
            reason: "Single-item cleanup target."
        )

        let historyStore = HistoryStore(folderName: "CleanMyMacTests-\(UUID().uuidString)")
        let viewModel = AppViewModel(
            permissionCenter: StubPermissionCenter(),
            scanner: StubScanner(),
            cleanupCoordinator: CleanupCoordinator(),
            historyStore: historyStore,
            finderBridge: FinderBridge()
        )

        viewModel.items = [first, second]
        viewModel.selectedItemIDs = [first.id]
        viewModel.focusedItemIDs = [first.id]

        viewModel.presentCleanupSheet(for: second)
        XCTAssertEqual(viewModel.selectedItemIDs, [first.id, second.id])

        viewModel.dismissCleanupSheet()

        XCTAssertEqual(viewModel.selectedItemIDs, [first.id])
        XCTAssertEqual(viewModel.focusedItemIDs, [first.id])
        XCTAssertNil(viewModel.cleanupPlan)
    }

    @MainActor
    func testCancelScanRestoresStableResultsAndIgnoresLateEvents() async throws {
        let existing = ScanItem(
            id: "existing",
            path: "/tmp/existing.log",
            kind: .file,
            byteSize: 120,
            lastUsedDate: nil,
            modifiedDate: .now,
            toolchain: nil,
            category: .logs,
            risk: .low,
            recommendation: .recommended,
            reason: "Existing stable result."
        )
        let incoming = ScanItem(
            id: "incoming",
            path: "/tmp/incoming.old",
            kind: .file,
            byteSize: 400,
            lastUsedDate: nil,
            modifiedDate: .distantPast,
            toolchain: nil,
            category: .oldFiles,
            risk: .medium,
            recommendation: .review,
            reason: "Late event after cancel."
        )

        let stableSnapshot = ScanSnapshot(
            target: .currentUser(),
            items: [existing],
            summaries: [existing].summaries(),
            startedAt: .now,
            endedAt: .now,
            totalMatchedBytes: existing.byteSize
        )

        let historyStore = HistoryStore(folderName: "CleanMyMacTests-\(UUID().uuidString)")
        let viewModel = AppViewModel(
            permissionCenter: StubPermissionCenter(),
            scanner: DelayedScanner(item: incoming),
            cleanupCoordinator: CleanupCoordinator(),
            historyStore: historyStore,
            finderBridge: FinderBridge()
        )

        viewModel.items = [existing]
        viewModel.scanSnapshot = stableSnapshot
        viewModel.selectedSection = .review
        viewModel.selectedCategory = .logs

        viewModel.startScan()
        try await Task.sleep(for: .milliseconds(20))
        viewModel.cancelScan()
        try await Task.sleep(for: .milliseconds(220))

        XCTAssertFalse(viewModel.isScanning)
        XCTAssertNil(viewModel.scanProgress)
        XCTAssertEqual(viewModel.items.map(\.id), [existing.id])
        XCTAssertEqual(viewModel.scanSnapshot?.items.map(\.id), [existing.id])
        XCTAssertEqual(viewModel.selectedSection, .review)
        XCTAssertEqual(viewModel.selectedCategory, .logs)
        XCTAssertEqual(viewModel.statusMessage, "Scan cancelled.")
        XCTAssertFalse(viewModel.items.contains(where: { $0.id == incoming.id }))
    }

    @MainActor
    func testViewModelRetainsFailedCleanupItems() async throws {
        let succeeded = ScanItem(
            id: "ok",
            path: "/tmp/ok.cache",
            kind: .file,
            byteSize: 100,
            lastUsedDate: nil,
            modifiedDate: nil,
            toolchain: nil,
            category: .devCaches,
            risk: .low,
            recommendation: .recommended,
            reason: "Safe cache."
        )
        let failed = ScanItem(
            id: "fail",
            path: "/tmp/fail.cache",
            kind: .file,
            byteSize: 200,
            lastUsedDate: nil,
            modifiedDate: nil,
            toolchain: nil,
            category: .devCaches,
            risk: .medium,
            recommendation: .review,
            reason: "Could not be trashed."
        )

        let cleanupCoordinator = MockCleanupCoordinator(result: CleanupResult(
            succeededPaths: [succeeded.path],
            failedItems: [CleanupFailure(path: failed.path, reason: "Locked")],
            reclaimedBytes: succeeded.byteSize,
            skippedBytes: failed.byteSize
        ))

        let historyStore = HistoryStore(folderName: "CleanMyMacTests-\(UUID().uuidString)")
        let viewModel = AppViewModel(
            permissionCenter: StubPermissionCenter(),
            scanner: StubScanner(),
            cleanupCoordinator: cleanupCoordinator,
            historyStore: historyStore,
            finderBridge: FinderBridge()
        )

        viewModel.items = [succeeded, failed]
        viewModel.scanSnapshot = ScanSnapshot(
            target: .internalVolume,
            items: [succeeded, failed],
            summaries: [succeeded, failed].summaries(),
            startedAt: .now,
            endedAt: .now,
            totalMatchedBytes: succeeded.byteSize + failed.byteSize
        )
        viewModel.selectedItemIDs = [succeeded.id, failed.id]
        viewModel.cleanupPlan = CleanupPlan(
            items: [succeeded, failed],
            estimatedReclaimedBytes: succeeded.byteSize + failed.byteSize,
            deleteMode: .moveToTrash,
            warnings: [],
            excludedPathsSnapshot: []
        )

        viewModel.executeCleanup()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.items.map(\.id), [failed.id])
        XCTAssertEqual(viewModel.selectedItemIDs, [failed.id])
        XCTAssertEqual(viewModel.lastCleanupResult?.failedItems.first?.path, failed.path)
    }

    func testScannerCapturesNodeModulesAsSingleDirectoryFinding() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let nodeModules = fixture.rootURL.appending(path: "Projects/App/node_modules", directoryHint: .isDirectory)
        try fixture.createDirectory(nodeModules)
        try fixture.createFile(at: nodeModules.appending(path: "left-pad/index.js"), size: 512)

        let scanner = FileSystemScanner(configuration: ScannerConfiguration(
            largeFileThresholdBytes: 10_000_000,
            oldFileCutoff: .distantPast,
            protectedSystemPrefixes: []
        ))

        let snapshot = try await collectSnapshot(from: scanner.scan(target: .custom([fixture.rootURL]), rules: []))

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.category, .devCaches)
        XCTAssertEqual(snapshot.items.first?.toolchain, "Node.js")
        XCTAssertEqual(snapshot.items.first?.recommendation, .recommended)
        XCTAssertEqual(snapshot.items.first?.sizing, .estimatedFastFolder)
        XCTAssertNotNil(snapshot.items.first?.capturedChildCount)
        XCTAssertGreaterThan(snapshot.items.first?.byteSize ?? 0, 0)
        XCTAssertTrue(snapshot.items.first?.path.hasSuffix("/node_modules") == true)
        XCTAssertFalse(snapshot.items.contains(where: { $0.path.contains("left-pad/index.js") }))
    }

    func testScannerHonorsExcludedPaths() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let excluded = fixture.rootURL.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
        let included = fixture.rootURL.appending(path: "Logs/build.log")
        try fixture.createDirectory(excluded)
        try fixture.createFile(at: excluded.appending(path: "project/build.db"), size: 2_048)
        try fixture.createFile(at: included, size: 512)

        let scanner = FileSystemScanner(configuration: ScannerConfiguration(
            largeFileThresholdBytes: 10_000_000,
            oldFileCutoff: .distantPast,
            protectedSystemPrefixes: []
        ))
        let rules = [UserRule(kind: .excludedPath, value: excluded.path)]

        let snapshot = try await collectSnapshot(from: scanner.scan(target: .custom([fixture.rootURL]), rules: rules))

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.category, .logs)
        XCTAssertTrue(snapshot.items.first?.path.hasSuffix("/Logs") == true)
    }

    func testScannerDoesNotFlagDeveloperManifestsAsInstallers() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        try fixture.createFile(at: fixture.rootURL.appending(path: "package.json"), size: 256)
        try fixture.createFile(at: fixture.rootURL.appending(path: "setup.py"), size: 256)
        try fixture.createFile(at: fixture.rootURL.appending(path: "android/build.gradle"), size: 256)

        let scanner = FileSystemScanner(configuration: ScannerConfiguration(
            largeFileThresholdBytes: 10_000_000,
            oldFileCutoff: .distantPast,
            protectedSystemPrefixes: []
        ))

        let snapshot = try await collectSnapshot(from: scanner.scan(target: .custom([fixture.rootURL]), rules: []))

        XCTAssertTrue(snapshot.items.isEmpty)
    }

    func testCleanupPlanAccumulatesWarningsAndBytes() {
        let coordinator = CleanupCoordinator()
        let items = [
            ScanItem(
                id: "1",
                path: "/tmp/archive.dmg",
                kind: .file,
                byteSize: 10_000,
                lastUsedDate: nil,
                modifiedDate: nil,
                toolchain: nil,
                category: .applicationBuilds,
                risk: .medium,
                recommendation: .review,
                reason: "Packaged release build."
            ),
            ScanItem(
                id: "2",
                path: "/tmp/docker",
                kind: .directory,
                byteSize: 200_000,
                lastUsedDate: nil,
                modifiedDate: nil,
                toolchain: "Docker",
                category: .devCaches,
                risk: .high,
                recommendation: .manualInspection,
                reason: "Docker data."
            ),
        ]

        let plan = coordinator.makePlan(items: items, selectedIDs: ["1", "2"], rules: [])

        XCTAssertEqual(plan.estimatedReclaimedBytes, 210_000)
        XCTAssertEqual(plan.deleteMode, .moveToTrash)
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertTrue(plan.warnings.contains(where: { $0.contains("high risk") }))
        XCTAssertTrue(plan.warnings.contains(where: { $0.contains("Application build artifacts") }))
    }

    func testScannerClassifiesBuildAndInstallerArtifacts() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let buildFolder = fixture.rootURL.appending(path: "Android/app/build", directoryHint: .isDirectory)
        let flutterToolState = fixture.rootURL.appending(path: "Flutter/.dart_tool", directoryHint: .isDirectory)
        let javaTarget = fixture.rootURL.appending(path: "Server/target", directoryHint: .isDirectory)
        let dmgFile = fixture.rootURL.appending(path: "Installers/CleanMyMac.dmg")
        let apkFile = fixture.rootURL.appending(path: "Exports/release.apk")

        try fixture.createDirectory(buildFolder)
        try fixture.createFile(at: buildFolder.appending(path: "outputs/main.o"), size: 1024)
        try fixture.createDirectory(flutterToolState)
        try fixture.createFile(at: flutterToolState.appending(path: "cache/snapshot.bin"), size: 4096)
        try fixture.createDirectory(javaTarget)
        try fixture.createFile(at: javaTarget.appending(path: "classes/App.class"), size: 2048)
        try fixture.createFile(at: dmgFile, size: 2048)
        try fixture.createFile(at: apkFile, size: 2048)

        let scanner = FileSystemScanner(configuration: ScannerConfiguration(
            largeFileThresholdBytes: 10_000_000,
            oldFileCutoff: .distantPast,
            protectedSystemPrefixes: []
        ))

        let snapshot = try await collectSnapshot(from: scanner.scan(target: .custom([fixture.rootURL]), rules: []))
        let categoriesByPath = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.path, $0.category) })

        XCTAssertEqual(categoriesByPath[buildFolder.path], .buildArtifacts)
        XCTAssertEqual(categoriesByPath[flutterToolState.path], .devCaches)
        XCTAssertEqual(categoriesByPath[javaTarget.path], .buildArtifacts)
        XCTAssertEqual(categoriesByPath[dmgFile.path], .applicationBuilds)
        XCTAssertEqual(categoriesByPath[apkFile.path], .applicationBuilds)
        XCTAssertEqual(snapshot.items.first(where: { $0.path == buildFolder.path })?.sizing, .estimatedFastFolder)
        XCTAssertEqual(snapshot.items.first(where: { $0.path == flutterToolState.path })?.sizing, .estimatedFastFolder)
        XCTAssertEqual(snapshot.items.first(where: { $0.path == javaTarget.path })?.sizing, .estimatedFastFolder)
        XCTAssertEqual(snapshot.items.first(where: { $0.path == buildFolder.path })?.recommendation, .recommended)
        XCTAssertFalse(categoriesByPath.keys.contains(buildFolder.appending(path: "outputs/main.o").path))
        XCTAssertFalse(categoriesByPath.keys.contains(flutterToolState.appending(path: "cache/snapshot.bin").path))
        XCTAssertFalse(categoriesByPath.keys.contains(javaTarget.appending(path: "classes/App.class").path))
    }

    func testScannerClassifiesAdditionalDeveloperToolingFolders() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let pythonVenv = fixture.rootURL.appending(path: "Python/.venv", directoryHint: .isDirectory)
        let nextBuild = fixture.rootURL.appending(path: "Web/.next", directoryHint: .isDirectory)
        let terraformCache = fixture.rootURL.appending(path: "Infra/.terraform", directoryHint: .isDirectory)
        let bazelOut = fixture.rootURL.appending(path: "Bazel/bazel-out", directoryHint: .isDirectory)

        try fixture.createDirectory(pythonVenv)
        try fixture.createFile(at: pythonVenv.appending(path: "bin/python"), size: 2048)
        try fixture.createDirectory(nextBuild)
        try fixture.createFile(at: nextBuild.appending(path: "server/app.js"), size: 1024)
        try fixture.createDirectory(terraformCache)
        try fixture.createFile(at: terraformCache.appending(path: "providers/provider.bin"), size: 2048)
        try fixture.createDirectory(bazelOut)
        try fixture.createFile(at: bazelOut.appending(path: "k8-fastbuild/bin/app"), size: 1024)

        let scanner = FileSystemScanner(configuration: ScannerConfiguration(
            largeFileThresholdBytes: 10_000_000,
            oldFileCutoff: .distantPast,
            protectedSystemPrefixes: []
        ))

        let snapshot = try await collectSnapshot(from: scanner.scan(target: .custom([fixture.rootURL]), rules: []))
        let categoriesByPath = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.path, $0.category) })

        XCTAssertEqual(categoriesByPath[pythonVenv.path], .devCaches)
        XCTAssertEqual(categoriesByPath[nextBuild.path], .buildArtifacts)
        XCTAssertEqual(categoriesByPath[terraformCache.path], .devCaches)
        XCTAssertEqual(categoriesByPath[bazelOut.path], .buildArtifacts)
    }

    private func collectSnapshot(from stream: AsyncThrowingStream<ScanEvent, Error>) async throws -> ScanSnapshot {
        for try await event in stream {
            if case let .completed(snapshot) = event {
                return snapshot
            }
        }
        XCTFail("Scan stream completed without a snapshot.")
        throw SnapshotCollectionError.missingCompletedEvent
    }
}

private enum SnapshotCollectionError: Error {
    case missingCompletedEvent
}

private struct MockCleanupCoordinator: CleanupCoordinating {
    let result: CleanupResult

    func makePlan(items: [ScanItem], selectedIDs: Set<String>, rules: [UserRule]) -> CleanupPlan {
        CleanupPlan(
            items: items.filter { selectedIDs.contains($0.id) },
            estimatedReclaimedBytes: items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.byteSize },
            deleteMode: .moveToTrash,
            warnings: [],
            excludedPathsSnapshot: []
        )
    }

    func execute(plan: CleanupPlan) -> CleanupResult {
        result
    }
}

private struct StubPermissionCenter: PermissionProviding {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(statuses: [
            PermissionStatus(
                requirement: .fullDiskAccess,
                state: .granted,
                details: "Granted",
                lastCheckedAt: .now
            ),
        ])
    }

    func openSystemSettings(for requirement: PermissionRequirement) {}
}

private struct StubScanner: ScanStreaming {
    func scan(target: ScanTarget, rules: [UserRule]) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct DelayedScanner: ScanStreaming {
    let item: ScanItem

    func scan(target: ScanTarget, rules: [UserRule]) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started(target))
                continuation.yield(.progress(ScanProgress(
                    phase: .inventory,
                    processedEntries: 120,
                    matchedItems: 0,
                    currentPath: "/tmp",
                    currentCategory: nil
                )))

                try? await Task.sleep(for: .milliseconds(80))
                continuation.yield(.item(item))

                try? await Task.sleep(for: .milliseconds(80))
                continuation.yield(.completed(ScanSnapshot(
                    target: target,
                    items: [item],
                    summaries: [item].summaries(),
                    startedAt: .now,
                    endedAt: .now,
                    totalMatchedBytes: item.byteSize
                )))
                continuation.finish()
            }
        }
    }
}

private final class TestFixture {
    let rootURL: URL
    private let fileManager = FileManager.default

    init() throws {
        rootURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createFile(at url: URL, size: Int) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(repeating: 0xAB, count: size)
        try data.write(to: url)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }
}
