---
description: Run a focused security audit on file operations, permissions, and data safety
---

# Security Review Workflow

Run this workflow to identify security vulnerabilities in file operations, permission handling, and data protection.

## Steps

1. **Read the Security Skill** — Load the full checklist:
   - Read `.agent/skills/security-review/SKILL.md`

2. **Verify No Network Calls** — The app claims 100% local operation:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && echo "=== URLSession/URLRequest ===" && grep -rn "URLSession\|URLRequest" Sources/ || echo "None ✅" && echo "=== Network Framework ===" && grep -rn "NWConnection\|NWListener\|NWEndpoint" Sources/ || echo "None ✅" && echo "=== Socket APIs ===" && grep -rn "CFSocket\|CFStream\|Socket(" Sources/ || echo "None ✅"
```

3. **Verify Trash-Only Deletion** — No permanent file removal:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && echo "=== trashItem (expected) ===" && grep -rn "trashItem" Sources/ && echo "=== removeItem (should NOT exist in production code) ===" && grep -rn "removeItem\|removeFile\|delete(" Sources/ --include="*.swift" | grep -v "Tests/" | grep -v ".build/" || echo "None ✅"
```

4. **Verify Protected Path Exclusions** — System paths are never scanned:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -A 10 "protectedSystemPrefixes" Sources/clean-my-mac/Services/Scanning/ScannerConfiguration.swift
```

5. **Audit Permission Probing** — Verify read-only access checks:
   - Review `PermissionCenter.swift` — ensure `contentsOfDirectory` (listing) is used, never file reading
   - Verify graceful degradation when FDA is not granted

6. **Audit Input Validation** — Check user-provided paths and patterns:
   - Review `addExcludedPath` and `addExcludedPattern` normalization
   - Review `globMatch` regex safety — potential ReDoS vectors
   - Review `customScanPath` handling from NSOpenPanel

7. **Audit Data Persistence** — Check stored data security:
   - Review `HistoryStore.swift` for atomic writes and permission-restricted directories
   - Verify no sensitive file contents are persisted — only paths and metadata

8. **Check Force Unwraps** — Potential crash vectors:
// turbo
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -rn '![^=]' Sources/ --include="*.swift" | grep -v '//\|import\|TODO\|FIXME\|!=\|isEmpty\|XCT' | head -20
```

9. **Generate Security Report** — Document findings with threat model and remediation steps.
