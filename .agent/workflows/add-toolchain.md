---
description: Add a new scan category or toolchain detection rule to the classifier
---

# Add New Toolchain/Category Workflow

Follow this workflow when adding support for detecting a new developer toolchain or scan category.

## Steps

1. **Define the Detection Pattern**:
   - What directory name(s) should be matched? (e.g., `.cargo`, `vendor/bundle`)
   - What file extensions should be matched? (e.g., `.wasm`, `.pyc`)
   - Which `ScanCategory` does it belong to? (`buildArtifacts`, `devCaches`, etc.)
   - What risk level? (`low`, `medium`, `high`)
   - What recommendation? (`recommended`, `review`, `manualInspection`)
   - Should the directory be captured as a single item? (`captureDirectory: true/false`)
   - What sizing strategy? (`estimatedFastFolder` for large dirs, `recursiveExact` for small)

2. **Add Directory Classification** — Edit `Sources/clean-my-mac/Services/Scanning/ScanClassifier.swift`:
   - Add a new case in `buildArtifactDirectoryDecision` or `developerCacheDirectoryDecision`
   - Or add to the `cacheRules` tuple array for path-based matching
   - Update `inferredToolchain` if the toolchain isn't already detected

3. **Add File Classification** (if applicable) — Edit `ScanClassifier.swift`:
   - Add new extensions to `buildArtifactExtensions`, `applicationBuildExtensions`, or `archiveExtensions`
   - Or add new manifest names to `safeDeveloperManifestNames`

4. **Add Estimate Policy** (if directory-based) — Edit `FileSystemScanner.swift`:
   - Add a new entry in `folderEstimatePolicy(for:decision:)` with appropriate `minimumBytes` and `averageBytesPerEntry`

5. **Write Tests** — Add to `Tests/CleanMyMacAppTests/CleanMyMacAppTests.swift`:
   ```swift
   func testScannerClassifies<NewToolchain>Directory() async throws {
       let fixture = try TestFixture()
       defer { fixture.cleanup() }
       
       let dir = fixture.rootURL.appending(path: "<pattern>", directoryHint: .isDirectory)
       try fixture.createDirectory(dir)
       try fixture.createFile(at: dir.appending(path: "sample.file"), size: 1024)
       
       let scanner = FileSystemScanner(configuration: ScannerConfiguration(
           largeFileThresholdBytes: 10_000_000,
           oldFileCutoff: .distantPast,
           protectedSystemPrefixes: []
       ))
       
       let snapshot = try await collectSnapshot(from: scanner.scan(target: .custom([fixture.rootURL]), rules: []))
       
       XCTAssertEqual(snapshot.items.first?.category, .<expectedCategory>)
       XCTAssertEqual(snapshot.items.first?.toolchain, "<expectedToolchain>")
   }
   ```

6. **Run Tests** — Verify everything passes:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift test --scratch-path .build 2>&1 | tail -15
```

7. **Update README** — If adding a major new toolchain, update the feature table in `README.md`.
