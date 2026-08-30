# Triangulum Product Shell Redesign Implementation Plan

> **For Codex:** Execute this plan inline with test-first checks where behavior changes; this pass is visual-only, so existing rendering tests are the regression gate.

**Goal:** Carry the approved Open Design field-instrument color and typography direction into the production SwiftUI shell without changing sensor, navigation, or persistence behavior.

**Architecture:** Reuse the existing Cel semantic tokens and shared instrument components so one small theme update reaches every screen. Limit screen-specific work to the dashboard chrome and capture action.

**Tech Stack:** SwiftUI, Swift Testing, xcodebuild

---

## Phase 1: Shared visual language

### Task 1: Update semantic color and type tokens

**Files:**
- Modify: `Triangulum/DesignSystem/CelestialTheme.swift`
- Verify: `TriangulumTests/CelComponentRenderingTests.swift`

- [x] Replace the blue-heavy palette with the approved navy, warm-white, teal, amber, violet, mint, and red roles.
- [x] Change display typography to DIN Alternate, primary readouts/body to Avenir Next, and keep SF Mono for telemetry labels.
- [x] Preserve existing token names so all current screens inherit the redesign without call-site churn.

### Task 2: Refine shared instrument surfaces

**Files:**
- Modify: `Triangulum/DesignSystem/CelestialComponents.swift`
- Verify: `TriangulumTests/CelComponentRenderingTests.swift`

- [x] Flatten card depth, tighten corners, and strengthen hairlines to match the field-instrument prototype.
- [x] Keep existing accessibility semantics and public component APIs unchanged.

## Phase 2: Product shell

### Task 3: Apply the approved hierarchy to the dashboard chrome

**Files:**
- Modify: `Triangulum/Views/ContentView.swift`

- [x] Use the new display/body roles in the header and console labels.
- [x] Map console destinations to the approved semantic accents.
- [x] Make capture the violet primary action while preserving the existing snapshot flow.

## Phase 3: Verification

### Task 4: Verify build and rendering safety

**Files:**
- Verify: `TriangulumTests/DesignSystemTests.swift`
- Verify: `TriangulumTests/CelComponentRenderingTests.swift`

- [x] Run the focused design-system tests with parallel testing disabled.
- [x] Build the Triangulum scheme for an available iOS Simulator.
- [x] Review the final diff for accidental behavior or architecture changes.
