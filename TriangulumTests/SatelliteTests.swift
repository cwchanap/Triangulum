//
//  SatelliteTests.swift
//  TriangulumTests
//
//  Unit tests for satellite tracking functionality
//

import Testing
import Foundation
import CoreLocation
@testable import Triangulum

// MARK: - TLE Parsing Tests

struct TLEParsingTests {

    // Real ISS TLE data for testing
    let issName = "ISS (ZARYA)"
    let issLine1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
    let issLine2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

    @Test func testTLEParsingValidData() {
        let tle = TLE(name: issName, line1: issLine1, line2: issLine2)

        #expect(tle != nil)
        #expect(tle?.name == "ISS (ZARYA)")
        #expect(tle?.noradId == 25544)
        #expect(tle?.line1 == issLine1)
        #expect(tle?.line2 == issLine2)
    }

    @Test func testTLEParsingOrbitalElements() {
        guard let tle = TLE(name: issName, line1: issLine1, line2: issLine2) else {
            Issue.record("TLE parsing failed unexpectedly")
            return
        }

        // Inclination should be around 51.64 degrees for ISS
        #expect(tle.inclination >= 51.0 && tle.inclination <= 52.0)

        // RAAN should be parsed
        #expect(tle.rightAscension >= 0 && tle.rightAscension <= 360)

        // Eccentricity for ISS is very low (near circular orbit)
        #expect(tle.eccentricity >= 0 && tle.eccentricity < 0.01)

        // Mean motion for ISS is about 15.5 revolutions/day
        #expect(tle.meanMotion >= 15.0 && tle.meanMotion <= 16.0)

        // Argument of perigee should be in valid range
        #expect(tle.argumentOfPerigee >= 0 && tle.argumentOfPerigee <= 360)

        // Mean anomaly should be in valid range
        #expect(tle.meanAnomaly >= 0 && tle.meanAnomaly <= 360)
    }

    @Test func testTLEParsingEpoch() {
        guard let tle = TLE(name: issName, line1: issLine1, line2: issLine2) else {
            Issue.record("TLE parsing failed unexpectedly")
            return
        }

        // Epoch should be a valid date in the past or near present
        let now = Date()
        let tenYearsAgo = now.addingTimeInterval(-10 * 365 * 24 * 60 * 60)

        #expect(tle.epoch > tenYearsAgo)
        #expect(tle.epoch < now.addingTimeInterval(365 * 24 * 60 * 60)) // Not more than 1 year in future
    }

    @Test func testTLEParsingInvalidLine1Prefix() {
        let invalidLine1 = "2 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let tle = TLE(name: issName, line1: invalidLine1, line2: issLine2)

        #expect(tle == nil)
    }

    @Test func testTLEParsingInvalidLine2Prefix() {
        let invalidLine2 = "1 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"
        let tle = TLE(name: issName, line1: issLine1, line2: invalidLine2)

        #expect(tle == nil)
    }

    @Test func testTLEParsingTooShortLines() {
        let shortLine = "1 25544"
        let tle = TLE(name: issName, line1: shortLine, line2: issLine2)

        #expect(tle == nil)
    }

    @Test func testTLEParsingEmptyName() {
        let tle = TLE(name: "  ", line1: issLine1, line2: issLine2)

        #expect(tle != nil)
        #expect(tle?.name == "")
    }

    @Test func testTLEEquality() {
        let tle1 = TLE(name: issName, line1: issLine1, line2: issLine2)
        let tle2 = TLE(name: issName, line1: issLine1, line2: issLine2)

        guard let parsedTle1 = tle1, let parsedTle2 = tle2 else {
            Issue.record("TLE parsing failed for testTLEEquality")
            return
        }

        #expect(parsedTle1 == parsedTle2)
    }

    @Test func testTLECodable() throws {
        guard let tle = TLE(name: issName, line1: issLine1, line2: issLine2) else {
            Issue.record("TLE parsing failed")
            return
        }

        let encoded = try JSONEncoder().encode(tle)
        let decoded = try JSONDecoder().decode(TLE.self, from: encoded)

        #expect(decoded.name == tle.name)
        #expect(decoded.noradId == tle.noradId)
        #expect(decoded.line1 == tle.line1)
        #expect(decoded.line2 == tle.line2)
        #expect(decoded.inclination == tle.inclination)
        #expect(decoded.meanMotion == tle.meanMotion)
    }
}

// MARK: - Satellite Position Tests

struct SatellitePositionTests {

    @Test func testPositionVisibility() {
        // Position above horizon
        let visiblePosition = SatellitePosition(
            eciX: 1000, eciY: 2000, eciZ: 3000,
            latitude: 45.0, longitude: -122.0, altitude: 400,
            azimuthDeg: 180, altitudeDeg: 45, rangeKm: 500
        )

        #expect(visiblePosition.isVisible == true)

        // Position below horizon
        let hiddenPosition = SatellitePosition(
            eciX: 1000, eciY: 2000, eciZ: 3000,
            latitude: 45.0, longitude: -122.0, altitude: 400,
            azimuthDeg: 180, altitudeDeg: -10, rangeKm: 1500
        )

        #expect(hiddenPosition.isVisible == false)
    }

    @Test func testPositionVisibilityNil() {
        // Position without topocentric data
        let unknownPosition = SatellitePosition(
            eciX: 1000, eciY: 2000, eciZ: 3000,
            latitude: 45.0, longitude: -122.0, altitude: 400,
            azimuthDeg: nil, altitudeDeg: nil, rangeKm: nil
        )

        #expect(unknownPosition.isVisible == false)
    }

    @Test func testPositionECIVector() {
        let position = SatellitePosition(
            eciX: 100.5, eciY: 200.5, eciZ: 300.5,
            latitude: 0, longitude: 0, altitude: 0,
            azimuthDeg: nil, altitudeDeg: nil, rangeKm: nil
        )

        let eci = position.eci
        #expect(eci.x == 100.5)
        #expect(eci.y == 200.5)
        #expect(eci.z == 300.5)
    }

    @Test func testPositionCodable() throws {
        let position = SatellitePosition(
            eciX: 100, eciY: 200, eciZ: 300,
            latitude: 45.5, longitude: -122.5, altitude: 408.5,
            azimuthDeg: 270.0, altitudeDeg: 30.0, rangeKm: 800.0
        )

        let encoded = try JSONEncoder().encode(position)
        let decoded = try JSONDecoder().decode(SatellitePosition.self, from: encoded)

        #expect(decoded.latitude == position.latitude)
        #expect(decoded.longitude == position.longitude)
        #expect(decoded.altitude == position.altitude)
        #expect(decoded.azimuthDeg == position.azimuthDeg)
        #expect(decoded.altitudeDeg == position.altitudeDeg)
    }
}

// MARK: - Satellite Pass Tests

struct SatellitePassTests {

    @Test func testPassDuration() {
        let riseTime = Date()
        let setTime = riseTime.addingTimeInterval(5 * 60) // 5 minutes later
        let peakTime = riseTime.addingTimeInterval(2.5 * 60) // 2.5 minutes

        let pass = SatellitePass(
            satelliteId: "ISS",
            satelliteName: "ISS (ZARYA)",
            riseTime: riseTime,
            peakTime: peakTime,
            setTime: setTime,
            maxAltitudeDeg: 45.0,
            riseAzimuthDeg: 270.0,
            setAzimuthDeg: 90.0
        )

        #expect(pass.duration == 300) // 5 minutes = 300 seconds
    }

    @Test func testPassDurationString() {
        let riseTime = Date()
        let setTime = riseTime.addingTimeInterval(5 * 60 + 30) // 5:30

        let pass = SatellitePass(
            satelliteId: "ISS",
            satelliteName: "ISS (ZARYA)",
            riseTime: riseTime,
            peakTime: riseTime.addingTimeInterval(2.5 * 60),
            setTime: setTime,
            maxAltitudeDeg: 45.0,
            riseAzimuthDeg: 270.0,
            setAzimuthDeg: 90.0
        )

        #expect(pass.durationString == "5:30")
    }

    @Test func testPassDurationStringShort() {
        let riseTime = Date()
        let setTime = riseTime.addingTimeInterval(45) // 45 seconds

        let pass = SatellitePass(
            satelliteId: "ISS",
            satelliteName: "ISS (ZARYA)",
            riseTime: riseTime,
            peakTime: riseTime.addingTimeInterval(22),
            setTime: setTime,
            maxAltitudeDeg: 10.0,
            riseAzimuthDeg: 270.0,
            setAzimuthDeg: 280.0
        )

        #expect(pass.durationString == "0:45")
    }

    @Test func testPassIdentifiable() {
        let pass1 = SatellitePass(
            satelliteId: "ISS",
            satelliteName: "ISS (ZARYA)",
            riseTime: Date(),
            peakTime: Date(),
            setTime: Date(),
            maxAltitudeDeg: 45.0,
            riseAzimuthDeg: 270.0,
            setAzimuthDeg: 90.0
        )

        let pass2 = SatellitePass(
            satelliteId: "ISS",
            satelliteName: "ISS (ZARYA)",
            riseTime: Date(),
            peakTime: Date(),
            setTime: Date(),
            maxAltitudeDeg: 45.0,
            riseAzimuthDeg: 270.0,
            setAzimuthDeg: 90.0
        )

        // Each pass should have unique ID
        #expect(pass1.id != pass2.id)
    }

    @Test func testPassCodable() throws {
        let pass = SatellitePass(
            satelliteId: "HST",
            satelliteName: "Hubble Space Telescope",
            riseTime: Date(),
            peakTime: Date().addingTimeInterval(120),
            setTime: Date().addingTimeInterval(240),
            maxAltitudeDeg: 60.0,
            riseAzimuthDeg: 45.0,
            setAzimuthDeg: 315.0
        )

        let encoded = try JSONEncoder().encode(pass)
        let decoded = try JSONDecoder().decode(SatellitePass.self, from: encoded)

        #expect(decoded.satelliteId == pass.satelliteId)
        #expect(decoded.satelliteName == pass.satelliteName)
        #expect(decoded.maxAltitudeDeg == pass.maxAltitudeDeg)
    }
}

// MARK: - Satellite Manager Tests

@MainActor
struct SatelliteManagerTests {

    @Test func testNextPassDebouncesWorkItem() async {
        let locationManager = LocationManager()
        locationManager.isAvailable = true
        locationManager.authorizationStatus = .authorizedWhenInUse

        let manager = SatelliteManager(locationManager: locationManager)
        let initialLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                                         altitude: 0.0,
                                         horizontalAccuracy: 5.0,
                                         verticalAccuracy: 5.0,
                                         timestamp: Date())
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [initialLocation])

        let issName = "ISS (ZARYA)"
        let issLine1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let issLine2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"
        guard let issTLE = TLE(name: issName, line1: issLine1, line2: issLine2) else {
            Issue.record("Failed to build ISS TLE for test")
            return
        }

        manager.applyTLEsForTesting([issTLE])

        // Wait for the initial work item to be scheduled
        let firstWorkItem = await waitForWorkItemChange(manager: manager, from: nil)

        // Trigger another location update to replace the work item
        let updatedLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195),
                                         altitude: 0.0,
                                         horizontalAccuracy: 5.0,
                                         verticalAccuracy: 5.0,
                                         timestamp: Date())
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [updatedLocation])

        let secondWorkItem = await waitForWorkItemChange(manager: manager, from: firstWorkItem)

        #expect(firstWorkItem != nil)
        #expect(secondWorkItem != nil)
        if let firstWorkItem, let secondWorkItem {
            #expect(firstWorkItem !== secondWorkItem)
            #expect(firstWorkItem.isCancelled == true)
        }
    }

    private func waitForWorkItemChange(
        manager: SatelliteManager,
        from previous: DispatchWorkItem?,
        timeoutSteps: Int = 200
    ) async -> DispatchWorkItem? {
        for _ in 0..<timeoutSteps {
            if manager.nextPassWorkItem !== previous {
                return manager.nextPassWorkItem
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return manager.nextPassWorkItem
    }
}

// MARK: - Satellite Tests

struct SatelliteTests {

    @Test func testSatelliteInitialization() {
        let satellite = Satellite(id: "TEST", name: "Test Satellite", noradId: 12345)

        #expect(satellite.id == "TEST")
        #expect(satellite.name == "Test Satellite")
        #expect(satellite.noradId == 12345)
        #expect(satellite.tle == nil)
        #expect(satellite.currentPosition == nil)
        #expect(satellite.nextPass == nil)
    }

    @Test func testTrackedSatellites() {
        let tracked = Satellite.tracked

        #expect(tracked.count == 3)

        // Verify ISS
        let iss = tracked.first { $0.id == "ISS" }
        #expect(iss != nil)
        #expect(iss?.noradId == 25544)

        // Verify Hubble
        let hubble = tracked.first { $0.id == "HST" }
        #expect(hubble != nil)
        #expect(hubble?.noradId == 20580)

        // Verify Tiangong
        let tiangong = tracked.first { $0.id == "CSS" }
        #expect(tiangong != nil)
        #expect(tiangong?.noradId == 48274)
    }

    @Test func testNoradIds() {
        let noradIds = Satellite.noradIds

        #expect(noradIds.count == 3)
        #expect(noradIds.contains(25544))  // ISS
        #expect(noradIds.contains(20580))  // Hubble
        #expect(noradIds.contains(48274))  // Tiangong
    }

    @Test func testSatelliteWithTLE() {
        let line1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let line2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"
        let tle = TLE(name: "ISS", line1: line1, line2: line2)

        var satellite = Satellite(id: "ISS", name: "ISS (ZARYA)", noradId: 25544)
        satellite.tle = tle

        #expect(satellite.tle != nil)
        #expect(satellite.tle?.meanMotion ?? 0 > 15)
    }

    @Test func testSatelliteCodable() throws {
        let satellite = Satellite(id: "TEST", name: "Test Satellite", noradId: 99999)

        let encoded = try JSONEncoder().encode(satellite)
        let decoded = try JSONDecoder().decode(Satellite.self, from: encoded)

        #expect(decoded.id == satellite.id)
        #expect(decoded.name == satellite.name)
        #expect(decoded.noradId == satellite.noradId)
    }
}

// MARK: - Satellite Position Snapshot Tests

struct SatellitePositionSnapshotTests {

    @Test func testSnapshotFromSatellite() {
        let position = SatellitePosition(
            eciX: 100, eciY: 200, eciZ: 300,
            latitude: 45.5, longitude: -122.5, altitude: 408.0,
            azimuthDeg: 180.0, altitudeDeg: 30.0, rangeKm: 800.0
        )

        var satellite = Satellite(id: "TEST", name: "Test Sat", noradId: 12345)
        satellite.currentPosition = position

        guard let snapshot = SatellitePositionSnapshot(from: satellite) else {
            Issue.record("Failed to build snapshot from satellite position")
            return
        }

        #expect(snapshot.id == "TEST")
        #expect(snapshot.name == "Test Sat")
        #expect(snapshot.latitude == 45.5)
        #expect(snapshot.longitude == -122.5)
        #expect(snapshot.altitudeKm == 408.0)
        #expect(snapshot.azimuthDeg == 180.0)
        #expect(snapshot.elevationDeg == 30.0)
        #expect(snapshot.isVisible == true)
    }

    @Test func testSnapshotFromSatelliteNoPosition() {
        let satellite = Satellite(id: "EMPTY", name: "Empty Sat", noradId: 99999)

        let snapshot = SatellitePositionSnapshot(from: satellite)

        #expect(snapshot == nil)
    }
}

// MARK: - SGP4 Propagator Tests

struct SGP4PropagatorTests {

    let issLine1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
    let issLine2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

    @Test func testPropagateBasic() {
        guard let tle = TLE(name: "ISS", line1: issLine1, line2: issLine2) else {
            Issue.record("TLE parsing failed")
            return
        }

        let position = SGP4Propagator.propagate(tle: tle, to: Date())

        // ISS altitude should be roughly 400-420 km
        #expect(position.altitude > 350 && position.altitude < 500)

        // Latitude should be within ISS inclination range
        #expect(position.latitude >= -52 && position.latitude <= 52)

        // Longitude should be valid
        #expect(position.longitude >= -180 && position.longitude <= 180)
    }

    @Test func testPropagateWithObserver() {
        guard let tle = TLE(name: "ISS", line1: issLine1, line2: issLine2) else {
            Issue.record("TLE parsing failed")
            return
        }

        // Observer in San Francisco
        let observerLat = 37.7749
        let observerLon = -122.4194

        let position = SGP4Propagator.propagate(
            tle: tle, to: Date(),
            observerLat: observerLat, observerLon: observerLon
        )

        // Topocentric coordinates should be calculated
        #expect(position.azimuthDeg != nil)
        #expect(position.altitudeDeg != nil)
        #expect(position.rangeKm != nil)

        // Azimuth should be 0-360
        #expect(position.azimuthDeg! >= 0 && position.azimuthDeg! <= 360)

        // Elevation should be -90 to 90
        #expect(position.altitudeDeg! >= -90 && position.altitudeDeg! <= 90)

        // Range should be positive
        #expect(position.rangeKm! > 0)
    }

    @Test func testECICoordinates() {
        guard let tle = TLE(name: "ISS", line1: issLine1, line2: issLine2) else {
            Issue.record("TLE parsing failed")
            return
        }

        let position = SGP4Propagator.propagate(tle: tle, to: Date())

        // ECI coordinates should give reasonable orbital radius
        let radius = sqrt(position.eciX * position.eciX +
                          position.eciY * position.eciY +
                          position.eciZ * position.eciZ)

        // Orbital radius = Earth radius (6378 km) + altitude (400 km) ~ 6778 km
        #expect(radius > 6500 && radius < 7000)
    }

    @Test func testCoordinateConversion() {
        // Test geodetic coordinate conversion
        let testECI = SIMD3<Double>(6778, 0, 0) // On equator at prime meridian
        let date = Date()

        let (lat, lon, alt) = SGP4Propagator.eciToGeodetic(eci: testECI, at: date)

        // Should be near equator
        #expect(abs(lat) < 10)

        // Altitude should be around 400 km
        #expect(alt > 350 && alt < 500)

        // Longitude depends on sidereal time but should be valid
        #expect(lon >= -180 && lon <= 180)
    }

    @Test func testFindNextPass() {
        guard let tle = TLE(name: "ISS", line1: issLine1, line2: issLine2) else {
            Issue.record("TLE parsing failed")
            return
        }

        // Look for pass from San Francisco
        let pass = SGP4Propagator.findNextPass(
            tle: tle,
            observerLat: 37.7749,
            observerLon: -122.4194,
            startDate: Date(),
            minElevation: 10.0,
            maxHours: 48.0
        )

        // ISS should have at least one visible pass in 48 hours
        // (may be nil if no pass meets minimum elevation)
        if let pass = pass {
            #expect(pass.riseTime < pass.peakTime)
            #expect(pass.peakTime < pass.setTime)
            #expect(pass.maxAltitudeDeg >= 10.0)
            #expect(pass.duration > 0)
        }
    }
}

// MARK: - TLE Cache Tests

@Suite(.serialized)  // Serialize to avoid race conditions with shared UserDefaults
struct TLECacheTests {

    // Create isolated cache for each test
    private func createTestCache() -> TLECache {
        let testDefaults = UserDefaults(suiteName: "TLECacheTests_\(UUID().uuidString)")!
        return TLECache(userDefaults: testDefaults, cacheKey: "test_tle_cache")
    }

    @Test func testCacheSaveAndLoad() {
        let cache = createTestCache()

        let line1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let line2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

        guard let tle = TLE(name: "ISS", line1: line1, line2: line2) else {
            Issue.record("TLE parsing failed")
            return
        }

            #expect(cache.save([tle]) == true)

        let loaded = cache.load()
        #expect(loaded != nil)
        #expect(loaded?.count == 1)
        #expect(loaded?.first?.name == "ISS")
    }

    @Test func testCacheFreshness() {
        let cache = createTestCache()

        // Initially should not have fresh cache
        #expect(cache.hasFreshCache == false)

        let line1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let line2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

        guard let tle = TLE(name: "ISS", line1: line1, line2: line2) else {
            Issue.record("TLE parsing failed for testCacheFreshness")
            return
        }
        #expect(cache.save([tle]) == true)

        // After saving, should have fresh cache
        #expect(cache.hasFreshCache == true)
    }

    @Test func testCacheClear() {
        let cache = createTestCache()

        let line1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let line2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

        guard let tle = TLE(name: "ISS", line1: line1, line2: line2) else {
            Issue.record("TLE parsing failed for testCacheClear")
            return
        }
        #expect(cache.save([tle]) == true)

        cache.clear()

        #expect(cache.load() == nil)
        #expect(cache.hasFreshCache == false)
    }

    @Test func testCacheLoadWithAge() {
        let cache = createTestCache()

        let line1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let line2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

        guard let tle = TLE(name: "ISS", line1: line1, line2: line2) else {
            Issue.record("TLE parsing failed for testCacheLoadWithAge")
            return
        }
        #expect(cache.save([tle]) == true)

        let cachedData = cache.loadWithAge()
        #expect(cachedData != nil)
        #expect(cachedData?.tles.count == 1)

        // Age should be very recent (less than 1 hour)
        if let ageInHours = cachedData?.ageInHours {
            #expect(ageInHours < 1.0)
        }
    }

    @Test func testCacheMultipleTLEs() {
        let cache = createTestCache()

        let tle1 = TLE(
            name: "ISS",
            line1: "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993",
            line2: "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"
        )

        let tle2 = TLE(
            name: "HUBBLE",
            line1: "1 20580U 90037B   24001.50000000  .00000500  00000-0  30000-4 0  9990",
            line2: "2 20580  28.4700 100.0000 0002500  90.0000 270.0000 15.09000000100001"
        )

        guard let parsedTle1 = tle1, let parsedTle2 = tle2 else {
            Issue.record("TLE parsing failed for testCacheMultipleTLEs")
            return
        }
        let tles = [parsedTle1, parsedTle2]

        #expect(cache.save(tles) == true)

        let loaded = cache.load()
        #expect(loaded?.count == tles.count)
    }

    @Test func testCacheHasCache() {
        let cache = createTestCache()

        #expect(cache.hasCache == false)

        let line1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let line2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

        guard let tle = TLE(name: "ISS", line1: line1, line2: line2) else {
            Issue.record("TLE parsing failed for testCacheHasCache")
            return
        }
        #expect(cache.save([tle]) == true)

        #expect(cache.hasCache == true)
    }

    @Test func testCacheAgeHours() {
        let cache = createTestCache()

        #expect(cache.cacheAgeHours == nil)

        let line1 = "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9993"
        let line2 = "2 25544  51.6400 208.5400 0006200 314.0000  90.0000 15.50000000100001"

        guard let tle = TLE(name: "ISS", line1: line1, line2: line2) else {
            Issue.record("TLE parsing failed for testCacheAgeHours")
            return
        }
        #expect(cache.save([tle]) == true)

        #expect(cache.cacheAgeHours != nil)
        #expect(cache.cacheAgeHours! < 1.0)
    }
}

// MARK: - Satellite Snapshot Data Tests

struct SatelliteSnapshotDataTests {

    @Test func testSnapshotDataCodable() throws {
        let position = SatellitePosition(
            eciX: 100, eciY: 200, eciZ: 300,
            latitude: 45.0, longitude: -122.0, altitude: 408.0,
            azimuthDeg: 180.0, altitudeDeg: 30.0, rangeKm: 800.0
        )

        var satellite = Satellite(id: "ISS", name: "ISS (ZARYA)", noradId: 25544)
        satellite.currentPosition = position

        guard let positionSnapshot = SatellitePositionSnapshot(from: satellite) else {
            Issue.record("Failed to build snapshot from satellite position")
            return
        }

        let snapshotData = SatelliteSnapshotData(
            capturedAt: Date(),
            satellites: [positionSnapshot],
            nextISSPass: nil
        )

        let encoded = try JSONEncoder().encode(snapshotData)
        let decoded = try JSONDecoder().decode(SatelliteSnapshotData.self, from: encoded)

        #expect(decoded.satellites.count == 1)
        #expect(decoded.satellites.first?.id == "ISS")
        #expect(decoded.nextISSPass == nil)
    }

    @Test func testSnapshotDataWithPass() throws {
        let pass = SatellitePass(
            satelliteId: "ISS",
            satelliteName: "ISS (ZARYA)",
            riseTime: Date(),
            peakTime: Date().addingTimeInterval(120),
            setTime: Date().addingTimeInterval(240),
            maxAltitudeDeg: 45.0,
            riseAzimuthDeg: 270.0,
            setAzimuthDeg: 90.0
        )

        let snapshotData = SatelliteSnapshotData(
            capturedAt: Date(),
            satellites: [],
            nextISSPass: pass
        )

        let encoded = try JSONEncoder().encode(snapshotData)
        let decoded = try JSONDecoder().decode(SatelliteSnapshotData.self, from: encoded)

        #expect(decoded.nextISSPass != nil)
        #expect(decoded.nextISSPass?.satelliteId == "ISS")
        #expect(decoded.nextISSPass?.maxAltitudeDeg == 45.0)
    }
}
