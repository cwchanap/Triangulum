//
//  AlmanacPresentationTests.swift
//  TriangulumTests
//
//  Pure presentation-copy and projection tests for the Almanac UI. Exact
//  user-visible copy (Sunrise/Sunset/polar, tide labels, chart summary,
//  station/datum/attribution, cache state, planning-only warning) is pinned
//  here through the pure helpers the views call, because SwiftUI's
//  accessibility tree is not reliably materialized synchronously through the
//  unit-test render seam.
//

import Testing
import Foundation
@testable import Triangulum

// File-scope (not static members): Swift Testing's @Suite members are each
// executed as a fresh instance, so shared fixtures live at file scope where
// every test can reference them without a Self prefix.

private let vancouverTimeZone = TimeZone(identifier: "America/Vancouver")!

/// An instant at the given wall-clock time in the given zone.
private func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                       timeZone: TimeZone = vancouverTimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let station = TideStation(
    id: "CHS-07385",
    provider: .canadaCHS,
    providerStationCode: "07385",
    name: "Vancouver Point Atkinson",
    latitude: 49.3299,
    longitude: -123.2594,
    timeZoneIdentifier: "America/Vancouver",
    datumLabel: "Chart Datum",
    supportsHourlyCurve: true
)

/// One deterministic day mirroring the -ui-testing fixture: hourly samples
/// between 1.0 m and 4.0 m, exact events at 00/06/12/18 local.
private func fixtureDay(_ date: LocalDate = LocalDate(year: 2026, month: 9, day: 15)) -> TideDay {
    let samples = (0..<24).map { hour in
        TideSample(
            instant: localDate(2026, 9, 15, hour),
            heightMetres: 2.5 + 1.5 * sin(Double(hour) / 24 * 2 * .pi)
        )
    }
    let events = [
        TideEvent(kind: .low, instant: localDate(2026, 9, 15, 0), heightMetres: 1.0),
        TideEvent(kind: .high, instant: localDate(2026, 9, 15, 6), heightMetres: 4.0),
        TideEvent(kind: .low, instant: localDate(2026, 9, 15, 12), heightMetres: 1.0),
        TideEvent(kind: .high, instant: localDate(2026, 9, 15, 18), heightMetres: 4.0)
    ]
    return TideDay(
        station: station,
        localDate: date,
        hourlySamples: samples,
        events: events,
        fetchedAt: localDate(2026, 9, 15, 12),
        sourceAttribution: TideProvider.canadaCHS.attribution
    )
}

@Suite
struct AlmanacPresentationTests {

    // MARK: - Time and time-zone copy

    @Test func destinationLocalClockTextUsesHHmmInTheGivenZone() {
        #expect(AlmanacText.clockText(localDate(2026, 9, 15, 6, 24), in: vancouverTimeZone) == "06:24")
        // Tokyo is the same instant, a different local time.
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(AlmanacText.clockText(localDate(2026, 9, 15, 6, 24), in: tokyo) == "22:24")
    }

    @Test func timeZoneLineShowsDaylightNameAndSignedUtcOffset() {
        // September 2026 in Vancouver is PDT (UTC−7); the tzdb change making
        // Vancouver permanent UTC-7 happens 2026-11-01, so this stays valid.
        let noon = localDate(2026, 9, 15, 12)
        #expect(AlmanacText.timeZoneLine(vancouverTimeZone, at: noon) == "Pacific Daylight Time · UTC−7")
    }

    @Test func countdownTextRoundsUpToTheNextMinute() {
        let start = localDate(2026, 9, 15, 9, 0)
        #expect(AlmanacText.countdownText(from: start, to: localDate(2026, 9, 15, 9, 12)) == "in 12m")
        #expect(AlmanacText.countdownText(from: start, to: localDate(2026, 9, 15, 12, 5)) == "in 3h 05m")
        // 61 seconds rounds up to two minutes rather than claiming "in 1m".
        #expect(AlmanacText.countdownText(from: start, to: start.addingTimeInterval(61)) == "in 2m")
        #expect(AlmanacText.countdownText(from: start, to: start) == "now")
    }

    // MARK: - Sunrise / Sunset / polar copy

    @Test func sunriseSunsetHeadlineLabels() {
        #expect(AlmanacSunView.sunriseLabel == "Sunrise")
        #expect(AlmanacSunView.daylightLabel == "Daylight")
        #expect(AlmanacSunView.sunsetLabel == "Sunset")
    }

    @Test func daylightDurationFormatsHoursAndMinutes() {
        let sunrise = localDate(2026, 9, 15, 6, 24)
        let sunset = localDate(2026, 9, 15, 19, 55)
        #expect(AlmanacSunView.daylightText(sunrise: sunrise, sunset: sunset, state: .normal) == "13h 31m")
    }

    @Test func polarCopyIsExplicitAndMissingValuesDash() {
        #expect(AlmanacSunView.daylightText(sunrise: nil, sunset: nil, state: .polarDay) == "24h 00m")
        #expect(AlmanacSunView.daylightText(sunrise: nil, sunset: nil, state: .polarNight) == "0h 00m")
        #expect(AlmanacSunView.daylightText(sunrise: nil, sunset: nil, state: .normal) == "—")
        #expect(AlmanacSunView.polarBannerText(state: .normal) == nil)
        #expect(AlmanacSunView.polarBannerText(state: .polarDay)
            == "Polar day — the sun stays above the horizon all day.")
        #expect(AlmanacSunView.polarBannerText(state: .polarNight)
            == "Polar night — the sun stays below the horizon all day.")
    }

    @Test func emptyEventListCopyPerSection() {
        #expect(AlmanacSunView.noMoreEventsText == "No more events today.")
        #expect(AlmanacSunView.emptyMorningText == "No morning events today.")
        #expect(AlmanacSunView.emptyEveningText == "No evening events today.")
    }

    // MARK: - SolarEventKind display names (approved Almanac copy)

    @Test func solarEventKindDisplayNames() {
        let expected: [SolarEventKind: String] = [
            .astronomicalDawn: "Astronomical dawn",
            .nauticalDawn: "Nautical dawn",
            .civilDawn: "Civil dawn",
            .sunrise: "Sunrise",
            .morningGoldenEnd: "Golden hour ends",
            .eveningGoldenStart: "Golden hour begins",
            .sunset: "Sunset",
            .civilDusk: "Civil dusk",
            .nauticalDusk: "Nautical dusk",
            .astronomicalDusk: "Astronomical dusk"
        ]
        for (kind, name) in expected {
            #expect(kind.displayName == name)
        }
        #expect(SolarEventKind.allCases.count == expected.count)
    }

    // MARK: - Next vs first tide

    @Test func tideKindDisplayNamesAndHeights() {
        #expect(TideEventKind.high.displayName == "High")
        #expect(TideEventKind.low.displayName == "Low")
        #expect(TideChartView.heightText(4.0) == "4.0 m")
        #expect(TideChartView.heightText(1.05) == "1.1 m")
    }

    @Test func summaryLeadsWithNextTideOnlyForToday() {
        let day = fixtureDay()
        #expect(AlmanacTidesView.summaryTitle(day: day, isToday: true) == "Next tide")
        #expect(AlmanacTidesView.summaryTitle(day: day, isToday: false) == "First tide")
    }

    @Test func summaryChoosesTheNextEventTodayAndTheFirstEventOtherwise() {
        let day = fixtureDay()
        let nineAM = localDate(2026, 9, 15, 9)

        // Today: the next event after now is the 12:00 low; countdown text
        // comes from the same projection the view renders.
        let next = AlmanacTidesView.summaryEvent(day: day, isToday: true, now: nineAM)
        #expect(next?.kind == .low)
        #expect(next?.instant == localDate(2026, 9, 15, 12))
        #expect(AlmanacText.countdownText(from: nineAM, to: next!.instant) == "in 3h 00m")

        // After today's last event nothing remains.
        #expect(AlmanacTidesView.summaryEvent(day: day, isToday: true, now: localDate(2026, 9, 15, 23)) == nil)
        #expect(AlmanacTidesView.summaryTitle(day: day, isToday: true) == "Next tide")

        // Another date: the first event leads regardless of the current time.
        let midnight = localDate(2026, 9, 15, 0, 30)
        let first = AlmanacTidesView.summaryEvent(day: day, isToday: false, now: midnight)
        #expect(first?.kind == .low)
        #expect(first?.instant == localDate(2026, 9, 15, 0))
    }

    @Test func eventlessDayCopy() {
        let day = TideDay(
            station: station,
            localDate: LocalDate(year: 2026, month: 9, day: 15),
            hourlySamples: [],
            events: [],
            fetchedAt: localDate(2026, 9, 15, 12),
            sourceAttribution: "test"
        )
        #expect(AlmanacTidesView.summaryTitle(day: day, isToday: true) == "No more events today")
        #expect(AlmanacTidesView.summaryTitle(day: day, isToday: false) == "No predicted events")
        #expect(AlmanacTidesView.summaryEvent(day: day, isToday: true, now: Date()) == nil)
    }

    @Test func nextEventExtensionStopsAfterTheLastEvent() {
        let day = fixtureDay()
        #expect(day.nextEvent(after: localDate(2026, 9, 15, 5))?.kind == .high)
        #expect(day.nextEvent(after: localDate(2026, 9, 15, 6))?.kind == .low)
        // Strictly-after: the event exactly at `instant` is not returned.
        #expect(day.nextEvent(after: localDate(2026, 9, 15, 12))?.instant == localDate(2026, 9, 15, 18))
        #expect(day.nextEvent(after: localDate(2026, 9, 15, 23)) == nil)
        // Outside the day (e.g. a previous day's instant) still finds events.
        #expect(day.nextEvent(after: localDate(2026, 9, 14, 23))?.kind == .low)
    }

    // MARK: - Chart summary

    @Test func chartAccessibilitySummaryPinsDateRangeAndEvents() {
        let day = fixtureDay()
        let summary = TideChartView.accessibilitySummary(
            samples: day.hourlySamples,
            events: day.events,
            timeZone: vancouverTimeZone
        )
        #expect(summary == "Tide chart for September 15, 2026. "
            + "Heights from 1.0 to 4.0 metres. "
            + "Low water 1.0 metres at 00:00. "
            + "High water 4.0 metres at 06:00. "
            + "Low water 1.0 metres at 12:00. "
            + "High water 4.0 metres at 18:00.")
    }

    @Test func chartSummarySurvivesMissingSamplesAndEvents() {
        // The helper's date sentence is projected from the points' instants,
        // so a fully empty day (no samples, no events) projects no sentence.
        // Real providers always publish both for a cached day; the chart is
        // only shown once a day exists.
        let day = TideDay(
            station: station,
            localDate: LocalDate(year: 2026, month: 9, day: 15),
            hourlySamples: [],
            events: [],
            fetchedAt: localDate(2026, 9, 15, 12),
            sourceAttribution: "test"
        )
        let summary = TideChartView.accessibilitySummary(
            samples: day.hourlySamples,
            events: day.events,
            timeZone: vancouverTimeZone
        )
        #expect(summary == "")
    }

    // MARK: - Station / datum / attribution text

    @Test func stationLineAndDistanceCopy() {
        #expect(AlmanacTidesView.distanceText(metres: 3_200) == "3.2 km away")
        #expect(AlmanacTidesView.distanceText(metres: 450) == "450 m away")
        #expect(AlmanacTidesView.distanceText(metres: 0) == "0 m away")
        #expect(AlmanacTidesView.stationLineText(station: station, distanceMetres: 3_200)
            == "Vancouver Point Atkinson · 3.2 km away")
    }

    @Test func datumAndAttributionCopy() {
        // Datum is displayed verbatim from the station's official catalogue row.
        #expect(station.datumLabel == "Chart Datum")
        #expect(TideProvider.canadaCHS.attribution == "Canadian Hydrographic Service")
        #expect(TideProvider.unitedStatesNOAA.attribution == "NOAA CO-OPS")
        #expect(TideProvider.japanJMA.attribution == "Japan Meteorological Agency")
        #expect(TideProvider.hongKongHKO.attribution == "Hong Kong Observatory")
        // The station card's source row shows the fetched day's attribution.
        let day = fixtureDay()
        #expect(day.sourceAttribution == "Canadian Hydrographic Service")
    }

    // MARK: - Required derivative-product notices

    /// Each non-U.S. provider's required notice wording is pinned verbatim
    /// (docs/almanac-tide-source-contracts.md); NOAA data is U.S. public
    /// domain, where source acknowledgment alone satisfies the contract.
    @Test func attributionNoticesCarryTheRequiredLegalWording() {
        #expect(TideProvider.canadaCHS.attributionNotice
            == "This product is not to be used for navigation. This product was made by or for Triangulum "
                + "and contains intellectual property (Data) of the Canadian Hydrographic Service of the "
                + "Department of Fisheries and Oceans. The copyrights in the Data are and remain the "
                + "property of His Majesty the King in Right of Canada and shall not be sold, licensed, "
                + "leased, assigned or given to a third party. The incorporation of the Data in this "
                + "product does not constitute an endorsement or an approval of this product by the "
                + "Canadian Hydrographic Service, the Department of Fisheries and Oceans or His Majesty "
                + "the King in Right of Canada.")
        #expect(TideProvider.japanJMA.attributionNotice?.contains("Source: Japan Meteorological Agency website") == true)
        #expect(TideProvider.japanJMA.attributionNotice?.contains("not presented as if created by the Government of Japan") == true)
        #expect(TideProvider.hongKongHKO.attributionNotice?.contains("Government of the Hong Kong Special Administrative Region") == true)
        #expect(TideProvider.hongKongHKO.attributionNotice?.contains("DATA.GOV.HK") == true)
        #expect(TideProvider.unitedStatesNOAA.attributionNotice == nil)
    }

    // MARK: - Station time-zone row

    @Test func stationTimeZoneRowShowsOnlyWhenTheStationZoneDiffersFromTheLocationZone() {
        let tokyoZone = TimeZone(identifier: "Asia/Tokyo")!
        let vancouverZone = TimeZone(identifier: "America/Vancouver")!
        // Same zone (the common case): no row.
        #expect(AlmanacTidesView.showsStationTimeZoneRow(stationZone: vancouverZone, locationZone: vancouverZone) == false)
        // A station across a zone boundary from the Almanac location: row.
        #expect(AlmanacTidesView.showsStationTimeZoneRow(stationZone: tokyoZone, locationZone: vancouverZone) == true)
        #expect(AlmanacTidesView.showsStationTimeZoneRow(stationZone: vancouverZone, locationZone: tokyoZone) == true)
        // Unknown zones hide the row rather than guess.
        #expect(AlmanacTidesView.showsStationTimeZoneRow(stationZone: nil, locationZone: vancouverZone) == false)
        #expect(AlmanacTidesView.showsStationTimeZoneRow(stationZone: vancouverZone, locationZone: nil) == false)
    }

    @Test func cacheStateFormattingDistinguishesCachedFromUpdated() {
        let fetchedAt = localDate(2026, 9, 15, 12)
        #expect(AlmanacTidesView.updatedRowText(fetchedAt: fetchedAt, isStale: false, timeZone: vancouverTimeZone)
            == "Updated Sep 15, 12:00")
        #expect(AlmanacTidesView.updatedRowText(fetchedAt: fetchedAt, isStale: true, timeZone: vancouverTimeZone)
            == "Cached Sep 15, 12:00")
        #expect(AlmanacTidesView.offlinePredictionsText == "Offline — showing cached predictions.")
    }

    @Test func planningOnlyWarningIsTheApprovedSentence() {
        #expect(AlmanacTidesView.planningOnlyWarningText
            == "Predictions are for planning only, not navigation.")
    }

    @Test func tideWarningMessagesCoverTheSpecStates() {
        #expect(AlmanacTidesView.tideWarningText(.unsupportedRegion)
            == "Tide predictions aren't available for this region.")
        #expect(AlmanacTidesView.tideWarningText(.providerUnavailable)
            == "The tide provider for this region is temporarily unavailable.")
        #expect(AlmanacTidesView.tideWarningText(.noStationNearby)
            == "No supported tide station nearby.")
        #expect(AlmanacTidesView.tideWarningText(.networkUnavailable)
            == "Couldn't reach the tide service.")
        #expect(AlmanacTidesView.tideWarningText(.invalidProviderResponse)
            == "The tide provider returned an unexpected response.")
        #expect(AlmanacTidesView.tideWarningText(.noPredictions)
            == "No tide predictions were published for these dates.")
    }

    @Test func tideLoadingStateCopy() {
        #expect(AlmanacTidesView.findingStationsText == "Finding nearby tide stations…")
        #expect(AlmanacTidesView.loadingPredictionsText(stationName: "Vancouver Point Atkinson")
            == "Loading predictions for Vancouver Point Atkinson…")
        #expect(AlmanacTidesView.chooseAnotherStationText == "Choose another station")
    }
}
