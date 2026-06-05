# Constellation Map UX Redesign

## Goal

Make the constellation map smoother and easier to recover from when the user pans or zooms in heading-follow mode. The current experience can keep rotating with live device heading while the user is exploring, which makes constellations feel like they move underneath the viewport.

## User Experience

The constellation map defaults to following the device heading. While the map is centered and unmodified, the sky remains aligned to the live compass heading.

When the user manually pans or pinches to zoom, the map enters an exploring state. In exploring state, the view freezes the heading that was active when exploration began. The user can inspect constellations without live heading updates rotating the projection. Panning and zooming continue to work as they do today, but they operate against that fixed heading.

A clear recenter/reorient control exits exploring state. It resets zoom to `1.0`, clears pan, and resumes live heading-follow. This is the primary recovery path when the user gets lost.

The UI shows a compact orientation status so users can tell whether the map is live or paused:

- `Live Heading 248°` when the map is following device heading.
- `Exploring 248°` when heading-follow is paused at a fixed heading.

## Controls

Footer controls remain compact and icon-based:

- Zoom out decreases zoom within the existing bounds.
- Zoom in increases zoom within the existing bounds.
- Recenter/reorient resets pan and zoom and resumes live heading-follow.

Remove the existing `Snap North` toggle from the constellation map menu. The redesigned default is heading-follow with temporary pause during manual exploration, so the primary constellation UX no longer presents north-up and heading-follow as competing modes.

## Architecture

Add explicit camera/orientation state to `ConstellationMapView`:

- `zoom`: existing persistent zoom scale.
- `pan`: existing persistent pan offset.
- `isExploring`: true after a user pan or zoom begins.
- `frozenHeading`: heading captured when exploration begins.

The drawing pipeline receives an effective heading:

- If exploring, use `frozenHeading`.
- Otherwise, use `locationManager.heading`.

Pan and zoom gestures both call a shared helper before mutating camera state. The helper captures the current live heading only when entering exploring state, so continued gestures preserve the same frozen orientation.

The recenter helper resets camera state and clears exploration:

- `zoom = 1.0`
- `pan = .zero`
- `isExploring = false`
- `frozenHeading = nil`

## Data Flow

`ConstellationMapView` remains the owner of camera state. No new model or persistence is needed.

The effective heading is passed consistently to:

- Rings and cardinal labels.
- Stars and constellation lines.
- Sun and Moon markers.
- Planet and satellite renderers.
- Compass status UI where relevant.

Existing `@AppStorage` settings for star labels, constellation labels, satellites, planets, catalog, large compass, and night vision remain unchanged.

## Error Handling

If heading is unavailable or invalid, use the same fallback behavior currently implied by `LocationManager.heading`. The exploring state stores whatever effective heading is available when exploration begins.

If the user taps recenter while location permissions are unavailable, the camera still resets pan and zoom. The map returns to live mode and uses the current heading value provided by the manager.

## Testing

Add focused unit coverage for a small camera-state helper rather than trying to assert Canvas pixels:

- Starting exploration captures the current heading.
- Repeated pan/zoom while already exploring does not replace the frozen heading.
- Effective heading uses frozen heading while exploring.
- Recenter clears pan, resets zoom, and resumes live heading.

Build the app after implementation with the existing Xcode project and scheme. If simulator availability blocks a full test run, at minimum run the focused unit tests and a Debug build.

## Out Of Scope

- New constellation data.
- Changes to astronomy calculations.
- Changes to map tile caching or MapKit views.
- Full visual redesign of the constellation art style.
