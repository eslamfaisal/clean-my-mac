---
name: security-review
description: Security audit for CleanMyMac — file system safety, permission handling, data persistence, sandboxing, and destructive-operation guardrails.
---

# Security Review Skill — CleanMyMac

Use this skill to audit the app for security vulnerabilities, unsafe file operations, privilege escalation risks, and data protection gaps.

---

## 1. Destructive Operations Safety

### 1.1 Trash-Only Deletion
- [ ] Confirm **all** file removal goes through `FileManager.trashItem(at:resultingItemURL:)` — never `removeItem(at:)`.
- [ ] Verify `DeleteMode` enum only has `.moveToTrash`. If a `permanentDelete` case is ever added, it must require elevated confirmation.
- [ ] Check that `CleanupCoordinator.execute(plan:)` does **not** follow symlinks — `trashItem` on a symlink should trash the link, not the target.

### 1.2 Confirmation Guardrails
- [ ] `presentCleanupSheet()` requires non-empty plan items before showing the sheet.
- [ ] Verify the cleanup confirmation sheet displays:
  - Total number of items being deleted.
  - Total reclaimable bytes.
  - Warning messages for high-risk items.
- [ ] Confirm no code path bypasses the confirmation sheet to execute cleanup directly.

### 1.3 Undo / Recovery
- [ ] macOS Trash supports "Put Back". Confirm trashed items retain their original path metadata.
- [ ] Document that the app does **not** empty Trash — that's the user's responsibility.

---

## 2. File System Permissions

### 2.1 Full Disk Access Detection
- [ ] `PermissionCenter.fullDiskAccessState()` probes protected directories (`Library/Mail`, `Library/Messages`, `Library/Safari`, `/Library/Application Support/com.apple.TCC`).
  - Verify these probes are **read-only** — never write or modify.
  - Confirm `contentsOfDirectory` is used (listing), not `contentsOfFile` (reading sensitive data).
- [ ] Validate that the app **gracefully degrades** when FDA is not granted — scanning continues on accessible paths without crashing.

### 2.2 Path Traversal Protection
- [ ] `ScannerConfiguration.shouldSkipTraversal` blocks system-critical paths (`/System`, `/dev`, `/proc`, `/private/var/vm`, `/cores`).
  - Verify these prefixes are **comprehensive** — consider adding `/sbin`, `/usr/sbin`, `/private/var/db`.
  - Confirm the check uses `standardizedFileURL.path` to prevent symlink-based bypass.
- [ ] Confirm `/Volumes/` is skipped to prevent scanning external/network drives unintentionally.

### 2.3 Symlink Handling
- [ ] Audit whether `FileManager.enumerator` follows symlinks. If yes, the scanner could:
  - Traverse outside the scan target.
  - Double-count files.
  - Attempt to trash files outside the user's intended scope.
- [ ] Recommend adding `.skipsHiddenFiles` option awareness (currently not skipped — is this intentional?).

---

## 3. Data Persistence Security

### 3.1 History & Rules Storage
- [ ] `HistoryStore` persists to `~/Library/Application Support/`. Verify:
  - The storage directory is created with restrictive permissions (owner-only: `0o700`).
  - JSON files are written atomically (`.atomic` write option) to prevent corruption.
  - No sensitive file paths are stored in plaintext that could leak user directory structure.

### 3.2 Pasteboard Safety
- [ ] `copyPath(of:)` writes to `NSPasteboard.general`. This exposes file paths to all apps. Acceptable but should be documented.

### 3.3 No Network Activity
- [ ] Confirm **zero** network calls exist in the entire codebase:
  - No `URLSession`, `URLRequest`, `NWConnection`, or socket usage.
  - No analytics, crash reporting, or update checking.
  - The README claims "100% local" — this must be verifiable.

---

## 4. Input Validation

### 4.1 User-Provided Paths
- [ ] `customScanPath` is set from `NSOpenPanel` (safe) or directly. Verify:
  - No path injection via crafted strings (e.g., `../../`).
  - `URL(fileURLWithPath:).standardizedFileURL` normalizes paths before use.
- [ ] `addExcludedPath` and `addExcludedPattern` normalize inputs. Confirm:
  - Empty strings are rejected.
  - Duplicate rules are not inserted.
  - Pattern rules don't allow ReDoS (regex denial of service) through crafted glob patterns.

### 4.2 Glob Pattern Safety
- [ ] `ScannerConfiguration.globMatch` converts user glob patterns to regex via `NSRegularExpression.escapedPattern`.
  - Verify the conversion handles edge cases: `*`, `**`, `?`, `[`, `]`.
  - Confirm no user input can produce a catastrophic backtracking regex.
  - The current implementation replaces `\\*` with `.*` — this is a basic glob-to-regex conversion. Consider using `fnmatch` or `NSPredicate` for safer glob matching.

---

## 5. App Signing & Distribution

### 5.1 Code Signing
- [ ] The DMG is ad-hoc signed. This means:
  - Gatekeeper will block first launch — users must right-click → Open.
  - No notarization = macOS Sequoia may refuse to run it entirely.
  - **Recommendation**: Implement proper Developer ID signing and notarization.

### 5.2 Info.plist Security
- [ ] Verify the built `.app` bundle's `Info.plist` declares only required entitlements.
- [ ] No `com.apple.security.temporary-exception` entitlements should be present.
- [ ] If Hardened Runtime is enabled, confirm JIT and unsigned memory entitlements are **not** granted.

---

## 6. Threat Model Summary

| Threat | Mitigation | Status |
|---|---|---|
| Accidental permanent deletion | Trash-only deletion | ✅ Verify |
| Scanning system-critical files | Protected prefix blocklist | ✅ Verify completeness |
| Symlink escape | Standardized path comparison | ⚠️ Audit enumerator options |
| Data leakage via persistence | Local-only storage | ✅ Verify no PII in logs |
| Network exfiltration | Zero network code | ✅ Grep verify |
| Regex DoS via glob patterns | Escaped pattern conversion | ⚠️ Audit edge cases |
| Unsigned binary trust | Ad-hoc signing | ❌ Recommend Developer ID |

---

## 7. Verification Commands

```bash
# Grep for any network-related imports or APIs
grep -rn "URLSession\|URLRequest\|NWConnection\|NWListener\|CFSocket\|CFStream" Sources/

# Grep for any permanent file deletion
grep -rn "removeItem\|removeFile\|contentsToMove" Sources/

# Grep for unsafe force unwraps
grep -rn '![^=]' Sources/ --include="*.swift" | grep -v '//' | grep -v 'TODO'

# Verify trashItem is the only deletion mechanism
grep -rn "trashItem" Sources/

# Check for hardcoded paths that might be sensitive
grep -rn "/Users/" Sources/
```
