# Unit Test Coverage Improvement Design

## Problem

Triangulum already has a meaningful Swift Testing suite, but the reported CI/Codecov coverage still has room to grow. The goal for this effort is to increase the reported unit-test coverage by approximately 10% while keeping the work low-risk, deterministic, and focused on files that actually count toward Codecov.

## Goals

- Increase the reported CI/Codecov unit-test coverage by roughly 10%.
- Keep the work inside `TriangulumTests` and avoid UI-test-only paths.
- Prefer deterministic tests over network-, timer-, or sensor-dependent behavior.
- Allow only small, behavior-preserving production refactors when they materially improve testability.

## Non-Goals

- Expanding `TriangulumUITests`.
- Spending time in `Triangulum/Views/**`, which is ignored by Codecov.
- Large architectural refactors that are not required to reach stable unit-test coverage gains.

## Current Context

- The repository uses Swift Testing (`@Test`, `#expect`, `#require`) rather than `XCTestCase`.
- CI measures unit-test coverage with `xcodebuild test -only-testing:TriangulumTests -enableCodeCoverage YES`.
- Codecov ignores `Triangulum/Views/**` and `TriangulumUITests/**`.
- Existing test suites already cover pressure history, snapshot persistence, widget ordering, keychain helpers, and several model-level astronomy calculations.

## Proposed Approach

Use a balanced strategy with one large coverage driver plus several low-risk supporting wins.

### Primary coverage driver

Target one large non-view file with weak direct test coverage:

1. `Triangulum/Managers/SatelliteManager.swift` (preferred)
2. `Triangulum/Managers/TileCacheManager.swift` (fallback if the satellite manager yields less coverage than expected or proves too awkward to test cleanly)

`SatelliteManager.swift` is the preferred first target because it is sizeable, contains important orchestration logic, and already exposes test-friendly seams such as injected cache state and `applyTLEsForTesting`.

### Supporting coverage wins

Add smaller deterministic tests around:

- `Triangulum/Config.swift`
- `Triangulum/Models/SensorSnapshot.swift`
- `Triangulum/Managers/CachedTileOverlay.swift`

These files should provide additional branch coverage with low implementation risk and help close the remaining gap if the primary target alone is not enough.

## Test Design

### SatelliteManager test focus

Prioritize deterministic state transitions and computed outputs:

- cache-backed startup behavior
- stale-cache handling
- snapshot generation
- location-dependent clearing/reset behavior

Avoid first-pass work on network fetch success paths or timer-heavy refresh loops unless an existing seam makes those branches easy to test reliably.

### Supporting file test focus

- `Config.swift`
  - API key validation
  - save/delete behavior
  - valid-key availability checks

- `SensorSnapshot.swift`
  - branches where weather data is present
  - branches where satellite snapshot data is present

- `CachedTileOverlay.swift`
  - tile URL generation
  - simple overlay behavior that does not require live tile downloads

## Testability Constraints

Some code in the app is naturally harder to unit test due to direct use of shared framework objects and background behavior:

- `URLSession.shared`
- timers and delayed work
- CoreMotion/CoreLocation/MapKit wrappers

To keep the work safe, the implementation should reuse existing test isolation patterns already present in the codebase:

- serialized suites for shared state
- per-test `UserDefaults` suites
- injected dependencies and testing initializers
- in-memory persistence where available

If a high-value branch is otherwise unreachable, small behavior-preserving refactors are allowed. These should be limited to narrow testability seams such as dependency injection, exposing a computed path through an internal helper, or similar non-behavioral structure changes.

## Execution Order

1. Capture the current CI-style unit-test coverage baseline.
2. Add tests for `SatelliteManager.swift`.
3. Re-run coverage and measure the delta.
4. Add supporting tests for `Config.swift`, `SensorSnapshot.swift`, and `CachedTileOverlay.swift`.
5. If needed, continue with `TileCacheManager.swift` as the fallback large target.
6. Stop when the target is reached or when the remaining gap clearly requires a larger refactor than this effort allows.

## Validation

Use the same measurement path before and after the change:

- run the existing unit-test command with `-only-testing:TriangulumTests`
- enable code coverage
- compare the resulting `xccov` report output

The work is successful when:

- all existing and new unit tests pass,
- the new tests are deterministic,
- and the reported unit-test coverage increases materially toward the 10% goal.

## Risks and Mitigations

- **Risk:** The preferred large target does not move coverage enough.
  - **Mitigation:** Preselect `TileCacheManager.swift` as the next large target.

- **Risk:** A promising branch depends on network or timer behavior.
  - **Mitigation:** Prefer state-based tests first and add only minimal seams when necessary.

- **Risk:** Small tests add confidence but not enough reported coverage.
  - **Mitigation:** Treat `Config`, `SensorSnapshot`, and `CachedTileOverlay` as supporting work, not the main coverage driver.
