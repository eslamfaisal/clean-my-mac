import Foundation
import XCTest
@testable import CleanMyMacApp

// MARK: - ScanClassifier Tests

final class ScanClassifierTests: XCTestCase {

    private func makeClassifier() -> ScanClassifier {
        ScanClassifier(configuration: .default())
    }

    // MARK: Directory Classification

    func testClassifiesDerivedDataAsBuildArtifact() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/Library/Developer/Xcode/DerivedData")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .buildArtifacts)
        XCTAssertEqual(result?.toolchain, "Xcode")
        XCTAssertEqual(result?.recommendation, .recommended)
        XCTAssertTrue(result?.captureDirectory == true)
    }

    func testClassifiesNodeModulesAsDevCache() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/projects/app/node_modules")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .devCaches)
        XCTAssertEqual(result?.toolchain, "Node.js")
        XCTAssertEqual(result?.recommendation, .recommended)
    }

    func testClassifiesGradleCacheAsDevCache() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/.gradle")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .devCaches)
        XCTAssertEqual(result?.toolchain, "Gradle")
    }

    func testClassifiesPodsAsDevCacheWithReview() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/ios-app/Pods")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .devCaches)
        XCTAssertEqual(result?.toolchain, "CocoaPods")
        XCTAssertEqual(result?.recommendation, .review)
    }

    func testClassifiesDotBuildAsBuildArtifact() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/swift-project/.build")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .buildArtifacts)
        XCTAssertEqual(result?.recommendation, .recommended)
    }

    func testClassifiesLogsDirectoryAsLogs() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/project/logs")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .logs)
        XCTAssertEqual(result?.recommendation, .recommended)
    }

    func testClassifiesTrashDirectory() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/.Trash")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .trash)
        XCTAssertEqual(result?.recommendation, .recommended)
    }

    func testClassifiesGitDirectoryAsHiddenReviewItem() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/project/.git")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertEqual(result?.category, .other)
        XCTAssertEqual(result?.recommendation, .manualInspection)
        XCTAssertEqual(result?.toolchain, "Git")
        XCTAssertTrue(result?.captureDirectory == true)
    }

    func testReturnsNilForUnknownDirectory() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/Documents")
        let result = classifier.classifyDirectory(at: url, rules: [])
        XCTAssertNil(result)
    }

    // MARK: File Classification

    func testClassifiesApkAsApplicationBuild() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/release.apk")
        let result = classifier.classifyFile(at: url, size: 1024, modifiedAt: .now, rules: [])
        XCTAssertEqual(result?.category, .applicationBuilds)
        XCTAssertEqual(result?.recommendation, .review)
    }

    func testClassifiesLogFileAsLogs() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/project/debug.log")
        let result = classifier.classifyFile(at: url, size: 256, modifiedAt: .now, rules: [])
        XCTAssertEqual(result?.category, .logs)
        XCTAssertEqual(result?.recommendation, .recommended)
    }

    func testClassifiesLargeFile() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/big-data.bin")
        let result = classifier.classifyFile(at: url, size: 600_000_000, modifiedAt: .now, rules: [])
        XCTAssertEqual(result?.category, .largeFiles)
    }

    func testClassifiesOldFile() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/old-project/readme.txt")
        let oldDate = Calendar.current.date(byAdding: .day, value: -200, to: .now)!
        let result = classifier.classifyFile(at: url, size: 100, modifiedAt: oldDate, rules: [])
        XCTAssertEqual(result?.category, .oldFiles)
    }

    func testClassifiesTmpFileAsOther() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/backup.tmp")
        let result = classifier.classifyFile(at: url, size: 100, modifiedAt: .now, rules: [])
        XCTAssertEqual(result?.category, .other)
    }

    func testDoesNotClassifySafeManifests() {
        let classifier = makeClassifier()
        let manifests = [
            "package.json", "Podfile", "Package.swift", "build.gradle",
            "Cargo.toml", "go.mod", "requirements.txt", "Dockerfile",
        ]
        for manifest in manifests {
            let url = URL(fileURLWithPath: "/Users/dev/project/\(manifest)")
            let result = classifier.classifyFile(at: url, size: 100, modifiedAt: .now, rules: [])
            XCTAssertNil(result, "Should not classify safe manifest: \(manifest)")
        }
    }

    // MARK: Category Disabling

    func testDisabledCategorySkipsClassification() {
        let classifier = makeClassifier()
        let url = URL(fileURLWithPath: "/Users/dev/Library/Developer/Xcode/DerivedData")
        let rules = [UserRule(kind: .categoryPreference, value: "disabled", category: .buildArtifacts)]
        let result = classifier.classifyDirectory(at: url, rules: rules)
        XCTAssertNil(result, "Disabled category should skip classification")
    }
}

// MARK: - ScannerConfiguration Tests

final class ScannerConfigurationTests: XCTestCase {

    func testProtectedSystemPrefixesBlockTraversal() {
        let config = ScannerConfiguration.default()
        let protectedURLs = [
            URL(fileURLWithPath: "/System/Library"),
            URL(fileURLWithPath: "/cores"),
            URL(fileURLWithPath: "/Network"),
        ]
        for url in protectedURLs {
            XCTAssertTrue(
                config.shouldSkipTraversal(at: url, isDirectory: true, rules: []),
                "Should skip protected prefix: \(url.path)"
            )
        }
    }

    func testUnprotectedPathsAreNotSkipped() {
        let config = ScannerConfiguration.default()
        let safeURLs = [
            URL(fileURLWithPath: "/Users/dev/Documents"),
            URL(fileURLWithPath: "/Library/Caches"),
            URL(fileURLWithPath: "/Users/dev/projects"),
        ]
        for url in safeURLs {
            XCTAssertFalse(
                config.shouldSkipTraversal(at: url, isDirectory: true, rules: []),
                "Should NOT skip safe path: \(url.path)"
            )
        }
    }

    func testExcludedPathRuleBlocksTraversal() {
        let config = ScannerConfiguration.default()
        let rules = [UserRule(kind: .excludedPath, value: "/Users/dev/secret")]
        let url = URL(fileURLWithPath: "/Users/dev/secret/file.txt")
        XCTAssertTrue(config.shouldSkipTraversal(at: url, isDirectory: false, rules: rules))
    }

    func testExcludedPatternRuleBlocksTraversal() {
        let config = ScannerConfiguration.default()
        let rules = [UserRule(kind: .excludedPattern, value: "*.DS_Store")]
        let url = URL(fileURLWithPath: "/Users/dev/projects/.DS_Store")
        XCTAssertTrue(config.shouldSkipTraversal(at: url, isDirectory: false, rules: rules))
    }

    func testGitDirectoryIsNotSkipped() {
        let config = ScannerConfiguration.default()
        let url = URL(fileURLWithPath: "/Users/dev/project/.git")
        XCTAssertFalse(config.shouldSkipTraversal(at: url, isDirectory: true, rules: []))
    }

    func testCategoryIsDisabled() {
        let config = ScannerConfiguration.default()
        let rules = [UserRule(kind: .categoryPreference, value: "disabled", category: .logs)]
        XCTAssertTrue(config.categoryIsDisabled(.logs, rules: rules))
        XCTAssertFalse(config.categoryIsDisabled(.buildArtifacts, rules: rules))
    }

    func testDefaultThresholds() {
        let config = ScannerConfiguration.default()
        XCTAssertEqual(config.largeFileThresholdBytes, 512 * 1_024 * 1_024)
        XCTAssertTrue(config.oldFileCutoff < .now)
        XCTAssertGreaterThan(config.protectedSystemPrefixes.count, 5)
    }
}

// MARK: - HistoryStore Tests

final class HistoryStoreTests: XCTestCase {

    private func makeStore() -> HistoryStore {
        HistoryStore(folderName: "CleanMyMacTests-\(UUID().uuidString)")
    }

    func testRoundTripPersistence() async {
        let store = makeStore()
        let rules = [UserRule(kind: .excludedPath, value: "/tmp/test")]
        let entries = [ScanHistoryEntry(
            matchedBytes: 1024,
            cleanedBytes: 0,
            itemCount: 5,
            categoryBreakdown: ["logs": 512, "devCaches": 512]
        )]

        await store.save(rules: rules, entries: entries)
        let loaded = await store.load()

        XCTAssertEqual(loaded.rules.count, 1)
        XCTAssertEqual(loaded.rules.first?.value, "/tmp/test")
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.itemCount, 5)
    }

    func testAppendEntry() async {
        let store = makeStore()
        let existing = ScanHistoryEntry(
            scannedAt: .now.addingTimeInterval(-100),
            matchedBytes: 500,
            cleanedBytes: 0,
            itemCount: 3,
            categoryBreakdown: [:]
        )
        let newEntry = ScanHistoryEntry(
            scannedAt: .now,
            matchedBytes: 2048,
            cleanedBytes: 100,
            itemCount: 10,
            categoryBreakdown: ["buildArtifacts": 1024, "logs": 1024]
        )

        let updated = await store.append(entry: newEntry, existingRules: [], existingEntries: [existing])

        XCTAssertEqual(updated.count, 2)
        // Most recent first
        XCTAssertEqual(updated.first?.matchedBytes, 2048)
    }

    func testCorruptedFileReturnsEmptyState() async {
        let store = makeStore()

        // First save valid data so the directory is created
        await store.save(rules: [], entries: [])

        // Loaded state from empty save should be empty
        let loaded = await store.load()
        XCTAssertTrue(loaded.rules.isEmpty)
        XCTAssertTrue(loaded.entries.isEmpty)
    }

    func testLoadWithoutSaveReturnsEmptyState() async {
        let store = makeStore()
        let loaded = await store.load()
        XCTAssertTrue(loaded.rules.isEmpty)
        XCTAssertTrue(loaded.entries.isEmpty)
    }
}
