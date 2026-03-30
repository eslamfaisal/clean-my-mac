---
description: Quick pre-release checklist — build, test, security, and distribution validation
---

# Pre-Release Review Workflow

Run this workflow before creating a new GitHub release to ensure the app is ready for distribution.

## Steps

1. **Clean Build** — Verify a clean release build succeeds:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && rm -rf .build && swift build -c release --scratch-path .build 2>&1 | tail -10
```

2. **Run All Tests** — Ensure no regressions:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift test --scratch-path .build 2>&1 | tail -30
```

3. **Security Quick Check** — Verify no unsafe patterns crept in:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && echo "=== Force Unwraps ===" && grep -rn '!$\|! \|!\.' Sources/ --include="*.swift" | grep -v 'import\|//\|TODO\|XCT\|!=\|isEmpty' | head -10 && echo "=== Network APIs ===" && grep -rn "URLSession\|URLRequest\|NWConnection\|NWListener" Sources/ || echo "None found ✅" && echo "=== Permanent Deletion ===" && grep -rn "removeItem\(at\|removeFile" Sources/ --include="*.swift" | grep -v "Tests/" || echo "None found ✅"
```

4. **Version Check** — Verify version consistency:
   - Check `Package.swift` for correct swift-tools-version
   - Check `scripts/package_dmg.sh` for version in Info.plist
   - Check git tags match the intended release version

5. **Package DMG** — Build the distributable:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && chmod +x scripts/package_dmg.sh && ./scripts/package_dmg.sh
```

6. **Verify DMG** — Inspect the packaged artifact:
// turbo
```bash
ls -la /Users/eslamfaisal/Desktop/work/clean-my-mac/dist/
```

7. **Update README** — Ensure the README reflects the current release:
   - Features list matches implemented functionality
   - Screenshots are current (or noted as pending)
   - Installation instructions are accurate
   - Roadmap is up to date

8. **Create Release** — Tag and push:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && git tag -a v<VERSION> -m "Release v<VERSION>" && git push origin v<VERSION>
```
   Then create a GitHub Release with the DMG attached.
