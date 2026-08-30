# Triangulum Product Shell Redesign Implementation Plan

> **For Codex:** Execute this plan inline with test-first checks where behavior changes. This pass refreshes the visual system AND replaces the split shell with a four-tab `TabView`, so both rendering tests and the tab UI test are the regression gate.

**Goal:** Carry the approved Open Design field-instrument color and typography direction into the production SwiftUI shell, and restructure top-level navigation from the split shell into a four-tab `TabView` (Live, Field, Footprint, Settings) with field-mode navigation in `FieldHubView`. Sensor and persistence behavior remain unchanged.

**Architecture:** Reuse the existing Cel semantic tokens and shared instrument components so one small theme update reaches every screen. `ContentView` now hosts a four-tab `TabView` driven by the `ProductTab` enum; the Field tab routes to `FieldHubView`, which offers a segmented picker for Map, Compass, and Sky modes. Screen-specific work spans the dashboard chrome, the tab shell, and the capture action.

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

### Task 4: Verify build, rendering, and navigation safety

**Files:**
- Verify: `TriangulumTests/DesignSystemTests.swift`
- Verify: `TriangulumTests/CelComponentRenderingTests.swift`
- Verify: `TriangulumUITests/TriangulumUITests.swift` (`testMobileShellDisplaysFourPrimaryTabs`)

- [x] Run the focused design-system tests with parallel testing disabled.
- [x] Build the Triangulum scheme for an available iOS Simulator.
- [x] Cover the new four-tab shell with `testMobileShellDisplaysFourPrimaryTabs` so navigation regressions are caught alongside rendering checks.
- [x] Review the final diff for accidental behavior or architecture changes.
