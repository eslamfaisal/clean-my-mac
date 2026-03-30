---
name: ui-ux-review
description: UI/UX audit for CleanMyMac — design system consistency, accessibility, responsive layout, interaction patterns, animations, and user flow completeness.
---

# UI/UX Review Skill — CleanMyMac

Use this skill to audit the app's visual design, interaction quality, accessibility compliance, and user flow completeness.

---

## 1. Design System Consistency

### 1.1 AppPalette & Theme Tokens
- [ ] Verify all views use `AppPalette` colors exclusively — no inline `Color(red:green:blue:)` or `.red/.blue/.green` outside `AppTheme.swift`.
- [ ] Confirm `GlassCardModifier` is applied consistently across all card-like containers (dashboard panels, inspector, history entries).
- [ ] Check `MetricBadge` and `TagPill` are reused where appropriate — no ad-hoc implementations of the same visual pattern.

### 1.2 Typography
- [ ] Verify consistent font usage:
  - `.system(size:weight:design:.rounded)` for numbers and metrics.
  - `.headline` / `.subheadline` for labels.
  - No raw font sizes used inconsistently across views.
- [ ] Check that long text (file paths, reasons) truncates gracefully with `lineLimit` and `truncationMode`.

### 1.3 Spacing & Padding
- [ ] Verify consistent spacing multiples (e.g., 4, 8, 12, 16, 20, 24) — no arbitrary values like `13`, `17`, `23`.
- [ ] Confirm `GlassCardModifier` padding (20pt) is consistent with content insets.
- [ ] Check that section dividers and group spacing follow a rhythm.

---

## 2. Dark Mode & Color Contrast

### 2.1 Dark-Mode-First Validation
- [ ] The app uses `.preferredColorScheme(.dark)`. Verify it's applied at the root level (`AppShellView` or `WindowGroup`).
- [ ] Check that **all** text has sufficient contrast against dark surfaces:
  - Primary text (`Color.primary`) on `AppPalette.surface` — minimum 4.5:1 ratio.
  - Secondary text (`.secondary`) on `AppPalette.surfaceRaised` — minimum 3:1 ratio.
- [ ] Verify `AppPalette.accent` (teal) and `AppPalette.warning` (orange-red) are distinguishable for color-blind users.

### 2.2 Light Mode Fallback
- [ ] If the user overrides to Light Mode, does the app degrade gracefully or break visually?
- [ ] Glassmorphism effects (opacity, blur) may look wrong in Light Mode — document this as a known limitation or handle it.

---

## 3. Responsive Layout

### 3.1 Window Sizing
- [ ] Verify minimum window size is set appropriately. The sidebar + content should not clip or overlap at small sizes.
- [ ] Test at these widths:
  - Compact: ~800×600 — sidebar should collapse or truncate gracefully.
  - Standard: ~1200×800 — full layout visible.
  - Wide: ~1920×1200 — content should not stretch excessively.
- [ ] Confirm `NavigationSplitView` or equivalent handles sidebar visibility toggle.

### 3.2 Table/List Responsiveness
- [ ] `ReviewWorkspaceView` contains a sortable, filterable table. Verify:
  - Column widths adapt to content.
  - Long file paths are truncated with a tooltip on hover.
  - Horizontal scrolling is available if needed.
- [ ] Empty state: When no items match a filter, show a descriptive empty view — not a blank space.

---

## 4. Interaction Patterns

### 4.1 Keyboard Shortcuts
- [ ] `⌘⇧R` (Scan) — verify it's discoverable in the menu bar.
- [ ] `⌘⇧⌫` (Clean) — verify it's disabled when no items are selected.
- [ ] Check for standard macOS shortcuts:
  - `⌘A` — Select All in Review Workspace.
  - `⌘F` — Focus search field.
  - `Escape` — Dismiss sheets and popovers.

### 4.2 Selection & Focus
- [ ] Checkbox selection in Review Workspace:
  - Single click toggles selection.
  - Shift+click selects a range (if supported).
  - "Select All" / "Deselect All" buttons are visible.
- [ ] `focusedItemIDs` drives the Inspector panel. Verify:
  - Single-clicking a row updates the inspector.
  - Multi-selecting does not crash the inspector (it shows the first focused item).

### 4.3 Context Menus
- [ ] Right-click on a scan item should offer:
  - Reveal in Finder
  - Open
  - Copy Path
  - Exclude Folder
  - Clean This Item
- [ ] Verify context menu actions are wired correctly.

### 4.4 Drag & Drop
- [ ] Consider whether folder drag-and-drop into the Scan Setup sheet is supported for custom paths.

---

## 5. User Flow Completeness

### 5.1 First Launch Experience
- [ ] New user with no prior scan:
  - Dashboard shows "Ready" state with permission guidance.
  - Clear call-to-action to start first scan.
  - No confusing empty states.
- [ ] Permission setup:
  - FDA guidance panel shows clear instructions.
  - "Open System Settings" button works and deep-links correctly.

### 5.2 Scan → Review → Clean Flow
- [ ] Verify the happy path:
  1. User clicks "Scan Mac" → Sheet appears with approach choices.
  2. Scan runs with live progress → Dashboard updates in real-time.
  3. Scan completes → Auto-navigate to Review tab.
  4. User reviews items → Selects checkboxes.
  5. User clicks "Clean Selected" → Confirmation sheet appears.
  6. User confirms → Items moved to Trash → Success message.
- [ ] Verify error paths:
  - Scan cancelled mid-way → Previous state restored.
  - Cleanup fails for some items → Clear failure messages shown.
  - No items match → Meaningful "all clean" message.

### 5.3 Edge Cases
- [ ] Zero scan results: Dashboard and Review should show encouraging "Your Mac is clean!" state.
- [ ] Very large scan (10,000+ items): UI remains responsive, table virtualizes/paginates.
- [ ] Rapid scan restarts: State machine correctly handles overlapping scan sessions.

---

## 6. Accessibility

### 6.1 VoiceOver
- [ ] All interactive elements have meaningful accessibility labels.
- [ ] Images and icons use `.accessibilityLabel()` modifiers.
- [ ] Custom views (`AppLogoView`, sparkle shapes) are marked as decorative with `.accessibilityHidden(true)`.

### 6.2 Dynamic Type
- [ ] Verify the app respects system text size settings where feasible.
- [ ] Fixed font sizes (e.g., `.system(size: 28)`) should be reviewed — consider using `@ScaledMetric`.

### 6.3 Reduce Motion
- [ ] If animations are present (gradient background circles), verify they respect `@Environment(\.accessibilityReduceMotion)`.

---

## 7. Micro-Animations & Polish

- [ ] Scan progress: Verify a smooth progress indicator (not just text updates).
- [ ] Sheet transitions: `.sheet` and `.confirmationDialog` should have smooth presentation.
- [ ] Selection feedback: Checkbox toggling should feel instant — no lag.
- [ ] Cleanup success: Consider a subtle success animation or haptic equivalent.

---

## 8. Verification Checklist

```bash
# Check for hardcoded colors outside AppTheme
grep -rn "Color(" Sources/clean-my-mac/Views/ | grep -v "AppPalette" | grep -v "AppTheme"

# Check for missing accessibility labels
grep -rn "accessibilityLabel\|accessibilityHint\|accessibilityValue" Sources/clean-my-mac/Views/ | wc -l

# Verify keyboard shortcut registration
grep -rn "keyboardShortcut" Sources/clean-my-mac/Views/
```
