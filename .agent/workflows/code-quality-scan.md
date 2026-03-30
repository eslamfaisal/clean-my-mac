---
description: Quick code quality scan — find common issues, smells, and standards violations
---

# Code Quality Quick Scan Workflow

A fast, automated workflow to surface common code quality issues without deep manual review.

// turbo-all

## Steps

1. **Build Check** — Ensure clean compilation:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift build --scratch-path .build 2>&1 | tail -10
```

2. **Test Check** — Verify tests pass:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && swift test --scratch-path .build 2>&1 | tail -15
```

3. **Force Unwraps** — Potential crash points:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -rn '![^=]' Sources/ --include="*.swift" | grep -v '//\|import\|TODO\|XCT\|!=\|isEmpty\|Bool' | head -20 || echo "None found ✅"
```

4. **Print Statements** — Should use os_log or Logger:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -rn 'print(' Sources/ --include="*.swift" || echo "None found ✅"
```

5. **TODO/FIXME/HACK Markers** — Technical debt:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -rn 'TODO\|FIXME\|HACK\|TEMP\|XXX' Sources/ --include="*.swift" || echo "None found ✅"
```

6. **Large Files** — Complexity hotspots:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && find Sources/ -name "*.swift" -exec wc -l {} + | sort -rn | head -10
```

7. **Hardcoded Colors Outside Theme** — Design system consistency:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -rn "Color(" Sources/clean-my-mac/Views/ --include="*.swift" | grep -v "AppPalette\|AppTheme\|//" | head -10 || echo "All colors use AppPalette ✅"
```

8. **Network API Check** — Verify no network code:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -rn "URLSession\|URLRequest\|NWConnection\|http://" Sources/ --include="*.swift" || echo "No network code ✅"
```

9. **Unsafe File Deletion Check** — Only trash, never permanent delete:
```bash
cd /Users/eslamfaisal/Desktop/work/clean-my-mac && grep -rn "removeItem\|removeFile" Sources/ --include="*.swift" | grep -v "Tests/" || echo "No permanent deletion ✅"
```

10. **Review Results** — Summarize findings and recommend next steps.
