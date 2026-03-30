---
description: Run a comprehensive review of the entire CleanMyMac app across all audit dimensions
---

# Full App Review Workflow

This workflow runs all review skills in sequence to produce a comprehensive audit report.

## Steps

1. **Build Verification** — Ensure the project compiles and tests pass before reviewing:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift build --scratch-path .build 2>&1 | tail -10
```

2. **Run Tests** — Verify the existing test suite passes:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift test --scratch-path .build 2>&1 | tail -20
```

3. **Architecture Review** — Read and execute the architecture review skill:
   - Read `.agent/skills/architecture-review/SKILL.md`
   - Audit MVVM layer separation, DI patterns, Swift 6 concurrency, error handling
   - Document findings

4. **Performance Review** — Read and execute the performance review skill:
   - Read `.agent/skills/performance-review/SKILL.md`
   - Audit scanning I/O, memory usage, UI responsiveness, concurrency patterns
   - Document findings

5. **Security Review** — Read and execute the security review skill:
   - Read `.agent/skills/security-review/SKILL.md`
   - Audit destructive operations, permissions, data persistence, input validation
   - Run security grep commands:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && echo "=== Network APIs ===" && grep -rn "URLSession\|URLRequest\|NWConnection" Sources/ || echo "None found" && echo "=== Permanent Deletion ===" && grep -rn "removeItem" Sources/ || echo "None found" && echo "=== Trash Usage ===" && grep -rn "trashItem" Sources/
```

6. **UI/UX Review** — Read and execute the UI/UX review skill:
   - Read `.agent/skills/ui-ux-review/SKILL.md`
   - Audit design system, dark mode, responsive layout, accessibility, user flows
   - Document findings

7. **Feature Compatibility Review** — Read and execute the feature compatibility review skill:
   - Read `.agent/skills/feature-compatibility-review/SKILL.md`
   - Audit macOS version support, architecture compatibility, file system edge cases
   - Document findings

8. **Test Coverage Review** — Read and execute the test coverage review skill:
   - Read `.agent/skills/test-coverage-review/SKILL.md`
   - Audit coverage gaps, missing tests, test quality
   - Document findings

9. **Build & Distribution Review** — Read and execute the build distribution review skill:
   - Read `.agent/skills/build-distribution-review/SKILL.md`
   - Audit packaging, code signing, CI readiness
   - Document findings

10. **Generate Report** — Compile all findings into a single artifact:
    - Create `full-review-report.md` with sections for each audit dimension
    - Categorize findings by severity: 🔴 Critical, 🟡 Warning, 🟢 Info
    - Include actionable recommendations with priority (P0/P1/P2)
