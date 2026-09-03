//
//  AlmanacViewModel.swift
//

import Combine
import CoreLocation
import Foundation

/// Main-actor state for the Almanac tab: shared location + rolling seven-day
/// strip driving the Sun and Tides sections.
///
/// Every location/station/range-changing action cancels superseded tasks and
/// replaces `requestGeneration`; async results apply only when the generation
/// still matches (the SatelliteManager token-checked application pattern).
@MainActor
final class AlmanacViewModel: ObservableObject {
    enum Section: String, CaseIterable { case sun, tides }

    @Published private(set) var location: AlmanacLocation?
    @Published private(set) var selectedDate: LocalDate?
    @Published private(set) var visibleDates: [LocalDate] = []
    @Published var section: Section = .sun {
        didSet {
            if section == .tides && oldValue != .tides {
                reloadTidesIfNeeded()
            }
        }
    }
    @Published private(set) var solarDay: SolarDay?
    @Published private(set) var stationContext: TideStationContext?
    @Published private(set) var tideDay: TideDay?
    @Published private(set) var tideIsStale = false
    @Published private(set) var tideWarning: TideLoadError?
    /// The last user-chosen FIXED location (never a Current-mode GPS fix), so
    /// the location sheet can always offer it and `selectedLocation` keeps
    /// meaning "the last valid fixed location" per spec.
    @Published private(set) var lastFixedLocation: AlmanacLocation?

    private var requestGeneration = UUID()
    /// Placemark resolutions track their own generation: starting one must
    /// not invalidate an in-flight tide load (and vice versa). Selection- and
    /// mode-changing paths still invalidate resolutions via
    /// `stopCurrentLocationObservation`.
    private var placemarkGeneration = UUID()

    /// The injected clock's current instant. Views anchor every "today" and
    /// countdown judgment here — never `Date()` — so the -ui-testing fixture
    /// clock drives deterministic copy and the date strip stays consistent
    /// with the view model's own date math.
    var currentDate: Date { now() }

    /// Destination-local today for `timeZone`, from the injected clock.
    func today(in timeZone: TimeZone) -> LocalDate {
        LocalDate(currentDate, in: timeZone)
    }

    private var locationMode: AlmanacLocationMode
    private var stationOverride: TideStationOverride?
    private var windowStart: LocalDate?

    private var tideTask: Task<Void, Never>?
    private var placemarkTask: Task<Void, Never>?
    private var locationObservation: AnyCancellable?
    private var pendingCoordinate: CLLocationCoordinate2D?
    private var coordinateProcessingScheduled = false
    /// Last placemark-resolved current coordinate; movement under 5 km reuses
    /// the placemark. Rapid GPS fixes can arrive out of order, so paired
    /// latitude/longitude deliveries are coalesced and only the latest fix
    /// processes (see `scheduleCoordinateProcessing`).
    private var lastResolvedCoordinate: CLLocationCoordinate2D?

    private let tideService: any TideServing
    private let locationResolver: any AlmanacLocationResolving
    private let preferencesStore: AlmanacPreferencesStore
    private let now: () -> Date
    /// Shared live manager, observed only in Current mode. Never mutated.
    private weak var locationManager: LocationManager?

    init(dependencies: AlmanacDependencies, locationManager: LocationManager? = nil) {
        self.tideService = dependencies.tideService
        self.locationResolver = dependencies.locationResolver
        self.preferencesStore = dependencies.preferencesStore
        self.now = dependencies.now
        self.locationManager = locationManager

        let preferences = preferencesStore.load()
        locationMode = preferences.mode
        stationOverride = preferences.stationOverride
        lastFixedLocation = preferences.selectedLocation
        // Restore the persisted location mode and last fixed location; the
        // selected date always restarts at destination-local today. In
        // Current mode the last fixed location is offered (location sheet)
        // but never pinned — the app follows the device instead.
        if let restored = preferences.selectedLocation, preferences.mode == .selected {
            location = restored
        }
        if let timeZone = location?.timeZone {
            let today = LocalDate(now(), in: timeZone)
            selectedDate = today
            windowStart = today
            visibleDates = (try? today.rollingSevenDays(in: timeZone).dates(in: timeZone)) ?? []
        }
        recomputeSolarDay()
    }

    // MARK: - Date window

    func selectDate(_ date: LocalDate) {
        applyDateSelection(date, movesWindow: false)
    }

    func moveWindow(byDays days: Int) {
        guard let timeZone = location?.timeZone, let current = selectedDate,
              let shifted = try? current.adding(days: days, in: timeZone) else { return }
        applyDateSelection(shifted, movesWindow: true)
    }

    func selectToday() {
        guard let timeZone = location?.timeZone else { return }
        applyDateSelection(LocalDate(now(), in: timeZone), movesWindow: true)
    }

    private func applyDateSelection(_ date: LocalDate?, movesWindow: Bool) {
        guard let date else { return }
        let dateChanged = date != selectedDate
        selectedDate = date
        if movesWindow { windowStart = date }
        refreshVisibleDates()
        recomputeSolarDay()
        if dateChanged {
            // The published day belongs to the old date; never show it under
            // the new selection (spec: failures preserve data only for the
            // SAME selection).
            resetTideState()
        }
        reloadTidesIfNeeded()
    }

    private func refreshVisibleDates() {
        guard let windowStart, let timeZone = location?.timeZone else {
            visibleDates = []
            return
        }
        visibleDates = (try? windowStart.rollingSevenDays(in: timeZone).dates(in: timeZone)) ?? []
    }

    // MARK: - Location

    /// Stores a resolved location selection. Per spec: reset date and window
    /// to today at the destination, clear any manual station override, and
    /// recompute immediately.
    func selectLocation(_ location: AlmanacLocation) {
        self.location = location
        locationMode = location.mode
        stationOverride = nil
        if location.mode == .selected {
            // A search selection is a FIXED location: it becomes the last
            // fixed place the sheet offers and the store persists.
            lastFixedLocation = location
            stopCurrentLocationObservation()
        }
        persistPreferences()

        if let timeZone = location.timeZone {
            let today = LocalDate(now(), in: timeZone)
            selectedDate = today
            windowStart = today
            refreshVisibleDates()
        }
        recomputeSolarDay()
        resetTideState()
        reloadTidesIfNeeded()
    }

    /// Switches to Current mode: observe the shared LocationManager and
    /// resolve the placemark on the first valid fix (and after ≥5 km moves).
    func useCurrentLocation() {
        guard locationManager != nil else { return }
        locationMode = .current
        startCurrentLocationObservation()
        persistPreferences()
    }

    // MARK: - Station override

    func selectStation(_ station: TideStation) {
        guard let location else { return }
        stationOverride = TideStationOverride(
            stationID: station.id,
            anchorLatitude: location.latitude,
            anchorLongitude: location.longitude
        )
        persistPreferences()
        resetTideState()
        reloadTidesIfNeeded()
    }

    func useNearestStation() {
        guard stationOverride != nil else { return }
        stationOverride = nil
        persistPreferences()
        resetTideState()
        reloadTidesIfNeeded()
    }

    // MARK: - Current-location observation

    private func startCurrentLocationObservation() {
        guard let locationManager else { return }
        stopCurrentLocationObservation()
        locationObservation = Publishers.CombineLatest(
            locationManager.$latitude,
            locationManager.$longitude
        )
        .sink { [weak self] latitude, longitude in
            Task { @MainActor [weak self] in
                self?.scheduleCoordinateProcessing(latitude: latitude, longitude: longitude)
            }
        }
        // The subscription delivers the current values immediately; the
        // placemark resolve runs through the same coalesced path.
    }

    private func stopCurrentLocationObservation() {
        locationObservation = nil
        placemarkTask?.cancel()
        // Invalidate any in-flight resolution so a late result can never
        // overwrite a manual selection or mode switch.
        placemarkGeneration = UUID()
    }

    /// Coalesces the paired latitude/longitude deliveries so one user-visible
    /// fix processes once, with the latest coordinate.
    private func scheduleCoordinateProcessing(latitude: Double, longitude: Double) {
        pendingCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard !coordinateProcessingScheduled else { return }
        coordinateProcessingScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.coordinateProcessingScheduled = false
            guard let coordinate = self.pendingCoordinate else { return }
            self.currentLocationDidChange(to: coordinate)
        }
    }

    private func currentLocationDidChange(to coordinate: CLLocationCoordinate2D) {
        // (0, 0) is LocationManager's unfixed default, not a real fix.
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return }

        // Override retention (Current mode): survive ordinary movement, clear
        // beyond 25 km from the anchor where it was selected.
        if let stationOverride,
           CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
               .distance(from: CLLocation(latitude: stationOverride.anchorLatitude, longitude: stationOverride.anchorLongitude)) > 25_000 {
            self.stationOverride = nil
            persistPreferences()
        }

        // Placemark reuse: resolve only on the first fix or ≥5 km movement.
        if let lastResolvedCoordinate,
           CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
               .distance(from: CLLocation(latitude: lastResolvedCoordinate.latitude, longitude: lastResolvedCoordinate.longitude)) < 5_000 {
            return
        }
        lastResolvedCoordinate = coordinate

        placemarkTask?.cancel()
        placemarkGeneration = UUID()
        let generation = placemarkGeneration
        placemarkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await self.locationResolver.resolveCurrentCoordinate(coordinate)
                guard self.placemarkGeneration == generation else { return }
                self.applyResolvedCurrentLocation(resolved)
            } catch {
                // Keep the previous placemark context; movement under
                // resolution failure is retried on the next ≥5 km move.
                guard self.placemarkGeneration == generation else { return }
                // The failed resolve invalidated nothing on the tide side,
                // but make sure the Tides section still has data for the
                // previous placemark (no-op unless a reload is warranted).
                self.reloadTidesIfNeeded()
            }
        }
    }

    private func applyResolvedCurrentLocation(_ resolved: AlmanacLocation) {
        let firstFix = location == nil
        location = resolved
        locationMode = .current
        if firstFix, let timeZone = resolved.timeZone {
            let today = LocalDate(now(), in: timeZone)
            selectedDate = today
            windowStart = today
            refreshVisibleDates()
        }
        recomputeSolarDay()
        persistPreferences()
        // A Current-mode fix is a NEW selection: clear the previous
        // selection's tide state before loading (and never treat the fix as
        // the persisted last fixed location).
        resetTideState()
        reloadTidesIfNeeded()
    }

    // MARK: - Solar

    private func recomputeSolarDay() {
        guard let location, let selectedDate, let timeZone = location.timeZone else {
            solarDay = nil
            return
        }
        solarDay = try? SolarDay(
            date: selectedDate,
            timeZone: timeZone,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    // MARK: - Tide loading

    /// Cancels superseded tide work, bumps the generation, and reloads only
    /// when the Tides section can need the data.
    private func reloadTidesIfNeeded() {
        tideTask?.cancel()
        requestGeneration = UUID()
        guard section == .tides else { return }
        tideTask = Task { await loadTides() }
    }

    /// Cache-first: resolve the station, publish any cached day immediately,
    /// stop on a fresh hit unless force-refreshing, otherwise refresh the
    /// current rolling seven-day strip and reload the selected day.
    func loadTides(forceRefresh: Bool = false) async {
        guard let location, let selectedDate else { return }
        let generation = requestGeneration
        do {
            try await performTideLoad(
                location: location,
                date: selectedDate,
                generation: generation,
                forceRefresh: forceRefresh
            )
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == generation else { return }
            tideWarning = Self.tideWarning(from: error)
        }
    }

    private func performTideLoad(
        location: AlmanacLocation,
        date: LocalDate,
        generation: UUID,
        forceRefresh: Bool
    ) async throws {
        let context = try await tideService.resolveStation(for: location, override: stationOverride)
        guard requestGeneration == generation else { return }
        stationContext = context
        tideWarning = nil

        if let publishedStale = try await publishCachedDay(station: context.selected, date: date, generation: generation),
           !publishedStale && !forceRefresh {
            return
        }

        let range = try date.rollingSevenDays(in: context.timeZone)
        _ = try await tideService.refreshRange(station: context.selected, range: range)
        guard requestGeneration == generation else { return }

        let publishedAfterRefresh = try await publishCachedDay(station: context.selected, date: date, generation: generation)
        // The cache read above suspends; a newer request may have superseded
        // this load (and published its own warning) while it was in flight.
        guard requestGeneration == generation else { return }
        if publishedAfterRefresh == nil {
            tideDay = nil
            tideIsStale = false
        }
        tideWarning = nil
    }

    /// Publishes the station's cached day for `date` when one exists, returning
    /// whether it was stale; nil means nothing was cached.
    private func publishCachedDay(station: TideStation, date: LocalDate, generation: UUID) async throws -> Bool? {
        guard let cached = try await tideService.cachedDay(station: station, date: date) else { return nil }
        guard requestGeneration == generation else { return cached.isStale }
        tideDay = cached.day
        tideIsStale = cached.isStale
        return cached.isStale
    }

    private static func tideWarning(from error: Error) -> TideLoadError {
        (error as? TideLoadError) ?? .networkUnavailable
    }

    /// Selection-changing actions clear the previous selection's tide state
    /// synchronously, before the replacement load starts, so a resolution or
    /// refresh failure for the new selection can never leave the old
    /// selection's predictions on screen. Same-selection reloads (section
    /// switches, pull-to-refresh, cache-first day reads) keep published data
    /// visible per spec.
    private func resetTideState() {
        stationContext = nil
        tideDay = nil
        tideIsStale = false
        tideWarning = nil
    }

    // MARK: - Persistence

    private func persistPreferences() {
        // `selectedLocation` always means the last FIXED location: a
        // Current-mode GPS fix is displayed but never persisted over it.
        try? preferencesStore.save(
            AlmanacPreferences(
                mode: locationMode,
                selectedLocation: lastFixedLocation,
                stationOverride: stationOverride
            )
        )
    }
}
