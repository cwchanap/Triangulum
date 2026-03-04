//
//  PlanetTests.swift
//  TriangulumTests
//
//  Unit tests for planet position calculations
//

import Testing
import Foundation
@testable import Triangulum

// MARK: - Planet Catalog Tests

struct PlanetCatalogTests {

    @Test func testCatalogHasFivePlanets() {
        #expect(Planet.catalog.count == 5)
    }

    @Test func testCatalogNames() {
        let names = Planet.catalog.map { $0.name }
        #expect(names.contains("Mercury"))
        #expect(names.contains("Venus"))
        #expect(names.contains("Mars"))
        #expect(names.contains("Jupiter"))
        #expect(names.contains("Saturn"))
    }

    @Test func testInnerPlanetFlags() {
        let inner = Planet.catalog.filter { $0.isInner }.map { $0.name }
        #expect(inner.sorted() == ["Mercury", "Venus"])
    }

    @Test func testOuterPlanetFlags() {
        let outer = Planet.catalog.filter { !$0.isInner }.map { $0.name }
        #expect(outer.sorted() == ["Jupiter", "Mars", "Saturn"])
    }
}

// MARK: - Planet Illumination Tests

struct PlanetIlluminationTests {

    // At superior conjunction (planet lon == sun lon), planet is fully lit
    @Test func testFullIlluminationAtSuperiorConjunction() {
        let k = ConstellationMapView.Astronomer.innerPlanetIllumination(planetLon: 90.0, sunLon: 90.0)
        #expect(abs(k - 1.0) < 0.001)
    }

    // At inferior conjunction (planet lon == sun lon + 180°), planet is new (dark side)
    @Test func testDarkAtInferiorConjunction() {
        let k = ConstellationMapView.Astronomer.innerPlanetIllumination(planetLon: 270.0, sunLon: 90.0)
        #expect(abs(k - 0.0) < 0.001)
    }

    // At eastern/western elongation (~90° separation), illumination is 50%
    @Test func testHalfIlluminationAtElongation() {
        let k = ConstellationMapView.Astronomer.innerPlanetIllumination(planetLon: 90.0, sunLon: 0.0)
        #expect(abs(k - 0.5) < 0.001)
    }

    @Test func testIlluminationRangeIsZeroToOne() {
        for angle in stride(from: 0.0, through: 360.0, by: 10.0) {
            let k = ConstellationMapView.Astronomer.innerPlanetIllumination(planetLon: angle, sunLon: 0.0)
            #expect(k >= 0.0 && k <= 1.0)
        }
    }
}

// MARK: - Planet Equatorial Coordinate Tests

struct PlanetEquatorialTests {

    let testDate = Date(timeIntervalSince1970: 1741000000)  // ~March 2026

    @Test func testAllPlanetsProduceValidCoordinates() {
        for planet in Planet.catalog {
            let eq = ConstellationMapView.Astronomer.planetEquatorial(planet: planet, date: testDate)
            // RA must be 0..24h
            #expect(eq.raHours >= 0.0 && eq.raHours < 24.0, "RA out of range for \(planet.name): \(eq.raHours)")
            // Dec must be -90..+90 degrees
            #expect(eq.decDeg >= -90.0 && eq.decDeg <= 90.0, "Dec out of range for \(planet.name): \(eq.decDeg)")
        }
    }

    @Test func testPlanetEclipticLongitudeRange() {
        for planet in Planet.catalog.filter({ $0.isInner }) {
            let lon = ConstellationMapView.Astronomer.planetEclipticLongitude(planet: planet, date: testDate)
            #expect(lon >= 0.0 && lon < 360.0, "Ecliptic lon out of range for \(planet.name): \(lon)")
        }
    }

    // Verify positions remain stable (not NaN/inf) over a year of dates
    @Test func testCoordinatesStableOverTime() {
        let oneDay: TimeInterval = 86400
        let start = testDate
        for dayOffset in stride(from: 0.0, through: 365.0, by: 30.0) {
            let date = start.addingTimeInterval(dayOffset * oneDay)
            for planet in Planet.catalog {
                let eq = ConstellationMapView.Astronomer.planetEquatorial(planet: planet, date: date)
                #expect(eq.raHours.isFinite, "\(planet.name) RA not finite at day \(dayOffset)")
                #expect(eq.decDeg.isFinite, "\(planet.name) Dec not finite at day \(dayOffset)")
            }
        }
    }
}

// MARK: - Planet Rise/Set Tests

struct PlanetRiseSetTests {

    let testDate = Date(timeIntervalSince1970: 1741000000)

    @Test func testReturnsResultForNormalLatitude() {
        // Mid-latitude observer where most planets rise and set
        let event = ConstellationMapView.Astronomer.nextPlanetEvent(
            planets: Planet.catalog,
            date: testDate,
            latDeg: 37.0,
            lonDeg: -122.0
        )
        // At mid-latitude, at least one planet should rise/set in the next 24h
        #expect(event != nil)
    }

    @Test func testEventLabelContainsPlanetName() {
        if let event = ConstellationMapView.Astronomer.nextPlanetEvent(
            planets: Planet.catalog,
            date: testDate,
            latDeg: 37.0,
            lonDeg: -122.0
        ) {
            let planetNames = Planet.catalog.map { $0.name }
            #expect(planetNames.contains(where: { event.label.hasPrefix($0) }))
        }
    }

    @Test func testEventLabelContainsRisesOrSets() {
        if let event = ConstellationMapView.Astronomer.nextPlanetEvent(
            planets: Planet.catalog,
            date: testDate,
            latDeg: 37.0,
            lonDeg: -122.0
        ) {
            #expect(event.label.contains("rises") || event.label.contains("sets"))
        }
    }

    @Test func testCircumpolarPlanetsSkippedAtPole() {
        // At latitude ~90° (North Pole), all planets near the ecliptic plane are circumpolar
        // or below horizon always; nextPlanetEvent may return nil since |cosH0| > 1
        // This just verifies it doesn't crash
        let event = ConstellationMapView.Astronomer.nextPlanetEvent(
            planets: Planet.catalog,
            date: testDate,
            latDeg: 89.9,
            lonDeg: 0.0
        )
        // No assertion needed - just verify no crash
        _ = event
    }
}
