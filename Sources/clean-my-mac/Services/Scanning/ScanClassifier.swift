import Foundation

struct ClassificationDecision: Sendable {
    let category: ScanCategory
    let risk: ScanRisk
    let recommendation: ScanRecommendation
    let toolchain: String?
    let reason: String
    let captureDirectory: Bool
}

struct ScanClassifier: Sendable {
    let configuration: ScannerConfiguration

    func classifyDirectory(at url: URL, rules: [UserRule]) -> ClassificationDecision? {
        let path = url.standardizedFileURL.path
        let lowercasedPath = path.lowercased()
        let name = url.lastPathComponent.lowercased()

        if configuration.categoryIsDisabled(.buildArtifacts, rules: rules) == false {
            if let decision = buildArtifactDirectoryDecision(for: lowercasedPath, name: name) {
                return decision
            }
        }

        if configuration.categoryIsDisabled(.devCaches, rules: rules) == false {
            if let decision = developerCacheDirectoryDecision(for: lowercasedPath, name: name) {
                return decision
            }
        }

        if configuration.categoryIsDisabled(.logs, rules: rules) == false,
           name == "logs" || lowercasedPath.contains("/logs/") {
            return ClassificationDecision(
                category: .logs,
                risk: .low,
                recommendation: .recommended,
                toolchain: inferredToolchain(for: lowercasedPath, default: nil),
                reason: "Log directories often accumulate stale diagnostic files.",
                captureDirectory: true
            )
        }

        if configuration.categoryIsDisabled(.trash, rules: rules) == false,
           lowercasedPath.contains("/.trash") {
            return ClassificationDecision(
                category: .trash,
                risk: .low,
                recommendation: .recommended,
                toolchain: nil,
                reason: "Items already live in Trash and are usually safe to clear.",
                captureDirectory: true
            )
        }

        return nil
    }

    func classifyFile(at url: URL, size: Int64, modifiedAt: Date?, rules: [UserRule]) -> ClassificationDecision? {
        let path = url.standardizedFileURL.path
        let lowercasedPath = path.lowercased()
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if safeDeveloperManifestNames.contains(name) || safeDeveloperManifestSuffixes.contains(where: { name.hasSuffix($0) }) {
            return nil
        }

        if configuration.categoryIsDisabled(.applicationBuilds, rules: rules) == false,
           applicationBuildExtensions.contains(ext) {
            return ClassificationDecision(
                category: .applicationBuilds,
                risk: .medium,
                recommendation: .review,
                toolchain: inferredToolchain(for: lowercasedPath, default: "Application Build"),
                reason: "Packaged application output is typically reproducible from the project, but may still be needed for shipping, QA, or rollback.",
                captureDirectory: false
            )
        }

        if configuration.categoryIsDisabled(.downloadsInstallers, rules: rules) == false,
           archiveExtensions.contains(ext) && (lowercasedPath.contains("/downloads/") || archiveKeywords.contains(where: { name.contains($0) })) {
            return ClassificationDecision(
                category: .downloadsInstallers,
                risk: .medium,
                recommendation: .review,
                toolchain: nil,
                reason: "Installer and archive files are often safe to remove after use, but confirm you no longer need them for setup or rollback.",
                captureDirectory: false
            )
        }

        if configuration.categoryIsDisabled(.logs, rules: rules) == false,
           ext == "log" || lowercasedPath.contains("/logs/") {
            return ClassificationDecision(
                category: .logs,
                risk: .low,
                recommendation: .recommended,
                toolchain: inferredToolchain(for: lowercasedPath, default: nil),
                reason: "Log files usually provide temporary diagnostic value only.",
                captureDirectory: false
            )
        }

        if configuration.categoryIsDisabled(.buildArtifacts, rules: rules) == false,
           buildArtifactExtensions.contains(ext) {
            return ClassificationDecision(
                category: .buildArtifacts,
                risk: .medium,
                recommendation: .review,
                toolchain: inferredToolchain(for: lowercasedPath, default: "Build Artifact"),
                reason: "Archive output is often restorable, but confirm it is no longer needed.",
                captureDirectory: false
            )
        }

        if configuration.categoryIsDisabled(.largeFiles, rules: rules) == false,
           size >= configuration.largeFileThresholdBytes {
            return ClassificationDecision(
                category: .largeFiles,
                risk: .medium,
                recommendation: .review,
                toolchain: inferredToolchain(for: lowercasedPath, default: nil),
                reason: "This file exceeds the large-file threshold and deserves review.",
                captureDirectory: false
            )
        }

        if configuration.categoryIsDisabled(.oldFiles, rules: rules) == false,
           let modifiedAt,
           modifiedAt < configuration.oldFileCutoff {
            return ClassificationDecision(
                category: .oldFiles,
                risk: .medium,
                recommendation: .review,
                toolchain: inferredToolchain(for: lowercasedPath, default: nil),
                reason: "This file has not been modified in over six months.",
                captureDirectory: false
            )
        }

        if configuration.categoryIsDisabled(.other, rules: rules) == false,
           name.hasSuffix(".tmp") || name.hasSuffix(".old") || name.hasSuffix(".bak") {
            return ClassificationDecision(
                category: .other,
                risk: .low,
                recommendation: .review,
                toolchain: nil,
                reason: "Temporary and backup-style files often linger after manual workflows.",
                captureDirectory: false
            )
        }

        return nil
    }

    private func buildArtifactDirectoryDecision(for lowercasedPath: String, name: String) -> ClassificationDecision? {
        if lowercasedPath.contains("/library/developer/xcode/deriveddata") || name == "deriveddata" {
            return ClassificationDecision(
                category: .buildArtifacts,
                risk: .low,
                recommendation: .recommended,
                toolchain: "Xcode",
                reason: "Xcode DerivedData can be rebuilt automatically.",
                captureDirectory: true
            )
        }

        if lowercasedPath.contains("/library/developer/xcode/archives")
            || name == ".build"
            || lowercasedPath.hasSuffix("/carthage/build")
            || name == "flutter_build"
            || name == ".cxx"
            || name == "intermediates"
            || name == ".next"
            || name == ".nuxt"
            || name == ".svelte-kit"
            || name == ".output"
            || name == "storybook-static"
            || name == "bazel-out"
            || name == "bazel-bin"
            || name == "bazel-testlogs"
            || name == "cmakefiles"
            || name.hasPrefix("cmake-build-")
            || lowercasedPath.contains("/library/developer/xcode/deriveddata/sourcepackages") {
            return ClassificationDecision(
                category: .buildArtifacts,
                risk: .low,
                recommendation: .recommended,
                toolchain: inferredToolchain(for: lowercasedPath, default: "Build System"),
                reason: "Generated build output can be recreated by the toolchain when needed.",
                captureDirectory: true
            )
        }

        if buildArtifactDirectoryNames.contains(name) {
            let recommendation: ScanRecommendation = name == "build" || name == "target" || name == "dist" ? .review : .recommended
            return ClassificationDecision(
                category: .buildArtifacts,
                risk: recommendation == .recommended ? .low : .medium,
                recommendation: recommendation,
                toolchain: inferredToolchain(for: lowercasedPath, default: "Project Output"),
                reason: "Known generated output folder. The scanner captures the folder once and skips its descendants to avoid noisy results.",
                captureDirectory: true
            )
        }

        return nil
    }

    private func developerCacheDirectoryDecision(for lowercasedPath: String, name: String) -> ClassificationDecision? {
        if name == "node_modules" {
            return ClassificationDecision(
                category: .devCaches,
                risk: .medium,
                recommendation: .review,
                toolchain: "Node.js",
                reason: "Dependency folders can be restored with a package install. The scanner captures the folder once and skips nested packages.",
                captureDirectory: true
            )
        }

        if name == ".dart_tool" || name == ".pub-cache" {
            return ClassificationDecision(
                category: .devCaches,
                risk: .low,
                recommendation: .recommended,
                toolchain: "Flutter",
                reason: "Flutter and Dart tool state can be regenerated from project metadata and package resolution.",
                captureDirectory: true
            )
        }

        if name == ".gradle" {
            return ClassificationDecision(
                category: .devCaches,
                risk: .low,
                recommendation: .recommended,
                toolchain: "Gradle",
                reason: "Gradle caches and wrapper state can be restored on demand.",
                captureDirectory: true
            )
        }

        if name == "pods" {
            return ClassificationDecision(
                category: .devCaches,
                risk: .medium,
                recommendation: .review,
                toolchain: "CocoaPods",
                reason: "Pods are generated from your Podfile and lockfile, but active iOS projects may still rely on the checked-in folder.",
                captureDirectory: true
            )
        }

        if ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".nox", ".terraform", ".terragrunt-cache", ".turbo", ".parcel-cache"].contains(name) {
            return ClassificationDecision(
                category: .devCaches,
                risk: .low,
                recommendation: .recommended,
                toolchain: inferredToolchain(for: lowercasedPath, default: "Developer Cache"),
                reason: "Tool-generated cache data can usually be rebuilt automatically.",
                captureDirectory: true
            )
        }

        if [".venv", "venv"].contains(name) {
            return ClassificationDecision(
                category: .devCaches,
                risk: .medium,
                recommendation: .review,
                toolchain: "Python",
                reason: "Python virtual environments are reproducible, but many active projects rely on them locally.",
                captureDirectory: true
            )
        }

        let cacheRules: [(String, String, String, ScanRisk, ScanRecommendation)] = [
            ("/.gradle/caches", "Gradle", "Gradle cache content often grows aggressively.", .low, .recommended),
            ("/.m2/repository", "Maven", "Maven dependency cache is reusable and can be restored on demand.", .low, .recommended),
            ("/.cargo/registry", "Rust", "Cargo registry cache can be repopulated from dependency metadata.", .low, .recommended),
            ("/.cargo/git", "Rust", "Cargo git checkouts can be restored automatically.", .low, .recommended),
            ("/go/pkg/mod", "Go", "Go module caches can be restored from go.mod and go.sum.", .low, .recommended),
            ("/library/caches/homebrew", "Homebrew", "Homebrew caches installers that can be downloaded again.", .low, .recommended),
            ("/library/caches/cocoapods", "CocoaPods", "Cached pod specs and archives can be recreated.", .low, .recommended),
            ("/library/developer/coresimulator", "CoreSimulator", "Simulator support data can occupy large amounts of disk.", .low, .recommended),
            ("/library/developer/xcode/ios devicesupport", "Xcode Device Support", "Older device support content can often be removed.", .low, .recommended),
            ("/library/developer/xcode/deriveddata/sourcepackages", "Swift Package Manager", "Resolved Swift package checkouts and artifacts can often be rebuilt from Package.resolved.", .low, .recommended),
            ("/.pnpm-store", "pnpm", "The pnpm store is safe to rebuild from package metadata.", .low, .recommended),
            ("/.npm", "npm", "npm cache content can be repopulated automatically.", .low, .recommended),
            ("/.yarn", "Yarn", "Yarn cache content can be repopulated automatically.", .low, .recommended),
            ("/library/caches/yarn", "Yarn", "Yarn cache content can be repopulated automatically.", .low, .recommended),
            ("/library/containers/com.docker.docker/data", "Docker", "Docker local data is often a major space consumer and requires review.", .high, .manualInspection),
        ]

        if let match = cacheRules.first(where: { lowercasedPath.contains($0.0) }) {
            return ClassificationDecision(
                category: .devCaches,
                risk: match.3,
                recommendation: match.4,
                toolchain: match.1,
                reason: match.2,
                captureDirectory: true
            )
        }

        return nil
    }

    private func inferredToolchain(for path: String, default defaultToolchain: String?) -> String? {
        if path.contains("xcode") { return "Xcode" }
        if path.contains("flutter") || path.contains("dart") || path.contains(".pub-cache") { return "Flutter" }
        if path.contains("node") || path.contains("npm") || path.contains("yarn") || path.contains("pnpm") { return "Node.js" }
        if path.contains("python") || path.contains("venv") || path.contains("__pycache__") || path.contains(".pytest_cache") || path.contains(".mypy_cache") { return "Python" }
        if path.contains("android") { return "Android" }
        if path.contains("gradle") { return "Gradle" }
        if path.contains("m2") || path.contains("maven") || path.contains("java") { return "Maven" }
        if path.contains("cargo") || path.contains("rust") { return "Rust" }
        if path.contains("/go/") || path.contains("gomod") { return "Go" }
        if path.contains("bazel") { return "Bazel" }
        if path.contains("cmake") { return "CMake" }
        if path.contains("terraform") || path.contains("terragrunt") { return "Terraform" }
        if path.contains("pods") || path.contains("cocoapods") { return "CocoaPods" }
        if path.contains("docker") { return "Docker" }
        return defaultToolchain
    }

    private var buildArtifactDirectoryNames: Set<String> {
        ["build", "dist", "out", "release", "debug", "target", "archives", "archive", "bin"]
    }

    private var buildArtifactExtensions: Set<String> {
        ["aar", "framework"]
    }

    private var applicationBuildExtensions: Set<String> {
        [
            "aab", "apk", "app", "appimage", "appx", "deb", "dmg", "ear",
            "exe", "ipa", "iso", "jar", "msi", "msix", "mpkg", "pkg",
            "rpm", "war", "xcarchive", "xip"
        ]
    }

    private var archiveExtensions: Set<String> {
        ["zip", "tar", "gz", "xz", "tgz", "bz2", "7z", "rar", "zst"]
    }

    private var archiveKeywords: [String] {
        ["archive", "backup", "bundle", "export", "release"]
    }

    private var safeDeveloperManifestNames: Set<String> {
        [
            "package.json", "package-lock.json", "npm-shrinkwrap.json", "yarn.lock",
            "pnpm-lock.yaml", "pnpm-workspace.yaml", "podfile", "podfile.lock",
            "cartfile", "cartfile.resolved", "package.swift", "package.resolved",
            "pubspec.yaml", "pubspec.lock", "build.gradle", "build.gradle.kts",
            "settings.gradle", "settings.gradle.kts", "gradle.properties",
            "requirements.txt", "requirements-dev.txt", "pipfile", "pipfile.lock",
            "poetry.lock", "pyproject.toml", "setup.py", "cargo.toml",
            "cargo.lock", "go.mod", "go.sum", "pom.xml", "gemfile",
            "gemfile.lock", "composer.json", "composer.lock", "cmakelists.txt",
            "dockerfile", "docker-compose.yml", "docker-compose.yaml", "makefile"
        ]
    }

    private var safeDeveloperManifestSuffixes: Set<String> {
        [".xcodeproj", ".xcworkspace", ".pbxproj"]
    }
}
