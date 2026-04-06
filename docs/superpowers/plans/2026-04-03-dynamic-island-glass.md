# Dynamic Island Pure Black & Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the “Dynamic Island” pill look premium with consistent compact/expanded alignment, while using a pure black visual style (no glass material).

**Architecture:** SwiftUI-only change in `ContentView.swift`. No changes to managers or business logic; only view styling and spacing.

**Tech Stack:** SwiftUI (pure colors), macOS app UI (`NSApplicationDelegateAdaptor`).

---

### Task 1: Update Dynamic Island outer shell visuals (pure black)

- [x] **Step 1: Modify outer pill container styling**

Changed in `ContentView.swift`:
- kept `.background(Color.black)` for the outer pill
- removed the thin `strokeBorder` overlay (pure black style)
- kept `.clipShape(RoundedRectangle(..., style: .continuous))` for smooth curve transitions
- reverted shadow parameters to match the pure black style

### Task 2: Fix top spacing alignment between compact/expanded

- [x] **Step 1: Compact state top padding removal**

Changed in `ContentView.swift`:
- removed `compactView`’s `.padding(.top, 4)` so the pill contents are vertically centered.

- [x] **Step 2: Expanded state header top spacing**

Changed in `ContentView.swift`:
- removed the initial `Spacer(minLength: 12)`
- added `.padding(.top, 10)` to the header block so the expanded view “seats” closer to the outer border curve.

### Task 3: Make internal cards match pure black look

- [x] **Step 1: Replace opaque card backgrounds**

Changed in `ContentView.swift`:
- replaced internal card backgrounds with `.background(Color.black.opacity(0.15))`
- removed per-card `strokeBorder` overlays (no glass/line style)

### Task 4: Verify build & lint

- [x] **Step 1: Build the project**

Command run:
`xcodebuild -project "Ai_land.xcodeproj" -scheme "Ai_land" -configuration Debug build`

- [x] **Step 2: Check lints for modified file**

Tool used:
`ReadLints` on `ContentView.swift`

Expected: no linter errors.

