//
//  TideProviderTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

/// Source-gate tests for the four official tide providers.
///
/// These tests open the checked-in fixture files captured live on 2026-09-01
/// (see `docs/almanac-tide-source-contracts.md`) and assert the real source
/// shapes, not just attribution strings.
struct TideProviderTests {

    // MARK: - Every enabled provider has readable, non-empty fixtures

    @Test func canonicalFixturesAreReadableAndNonEmpty() throws {
        let required = [
            "CHS/stations-vancouver.json",
            "CHS/vancouver-hourly.json",
            "CHS/vancouver-hilo.json",
            "NOAA/stations-selection.json",
            "NOAA/san-francisco-hourly.json",
            "NOAA/san-francisco-hilo.json",
            "JMA/tokyo-station.txt",
            "JMA/tokyo-2026.txt",
            "HKO/tai-po-kau-2026-hourly.csv",
            "HKO/tai-po-kau-2026-hilo.csv"
        ]
        for path in required {
            #expect(try !AlmanacFixtureLoader.data(path).isEmpty)
        }
    }

    // MARK: - Provider gate

    @Test func productionEnablementIsTheApprovedProviderGate() {
        // All four providers with recorded source contracts are enabled in
        // the production default (docs/almanac-tide-source-contracts.md).
        // CHS is enabled because Triangulum is distributed free of charge for
        // non-commercial use, satisfying the CHS licence's prohibition on
        // derivative products made for sale or profit. The enum case stays
        // distinguishable from unsupported geography regardless.
        #expect(TideProvider.enabled == [.canadaCHS, .unitedStatesNOAA, .japanJMA, .hongKongHKO])
        #expect(TideProvider.allCases.contains(.canadaCHS))
        #expect(TideProvider.enabled.contains(.canadaCHS))
    }

    @Test func attributionNamesOfficialSources() {
        #expect(TideProvider.canadaCHS.attribution == "Canadian Hydrographic Service")
        #expect(TideProvider.unitedStatesNOAA.attribution == "NOAA CO-OPS")
        #expect(TideProvider.japanJMA.attribution == "Japan Meteorological Agency")
        #expect(TideProvider.hongKongHKO.attribution == "Hong Kong Observatory")
    }

    // MARK: - CHS shape

    private struct CHSStation: Decodable {
        let code: String
        let id: String
        let officialName: String
        let latitude: Double
        let longitude: Double
        let timeSeries: [CHSTimeSeries]
    }

    private struct CHSTimeSeries: Decodable {
        let code: String
    }

    private struct CHSDataPoint: Decodable {
        let eventDate: String
        let value: Double
    }

    @Test func chsStationFixtureDecodesVancouverWithBothPredictionSeries() throws {
        let stations = try JSONDecoder().decode([CHSStation].self, from: AlmanacFixtureLoader.data("CHS/stations-vancouver.json"))
        #expect(stations.count == 1)
        let vancouver = try #require(stations.first)
        #expect(vancouver.code == "07735")
        #expect(vancouver.officialName == "Vancouver")
        let series = Set(vancouver.timeSeries.map(\.code))
        #expect(series.contains("wlp"))
        #expect(series.contains("wlp-hilo"))
    }

    @Test func chsHourlyFixtureDecodesToHourlyRows() throws {
        let points = try JSONDecoder().decode([CHSDataPoint].self, from: AlmanacFixtureLoader.data("CHS/vancouver-hourly.json"))
        #expect(points.count == 25) // 2026-03-01 00:00Z … 2026-03-02 00:00Z inclusive
    }

    @Test func chsHiloFixtureDecodesToSparseHighLowEvents() throws {
        let points = try JSONDecoder().decode([CHSDataPoint].self, from: AlmanacFixtureLoader.data("CHS/vancouver-hilo.json"))
        #expect(points.count == 4)
    }

    // MARK: - NOAA shape

    private struct NOAAStationCatalogue: Decodable {
        let stations: [NOAAStation]
    }

    private struct NOAAStation: Decodable {
        let id: String
        let name: String
        let type: String
    }

    private struct NOAAPredictions: Decodable {
        let predictions: [NOAAPrediction]
    }

    private struct NOAAPrediction: Decodable {
        let t: String
        let value: String
        let type: String?

        enum CodingKeys: String, CodingKey {
            case t
            case value = "v"
            case type
        }
    }

    @Test func noaaStationSelectionDecodesReferenceAndSubordinate() throws {
        let catalogue = try JSONDecoder().decode(NOAAStationCatalogue.self, from: AlmanacFixtureLoader.data("NOAA/stations-selection.json"))
        #expect(catalogue.stations.count == 2)
        #expect(catalogue.stations.contains { $0.id == "9414290" && $0.type == "R" })
        #expect(catalogue.stations.contains { $0.type == "S" })
    }

    @Test func noaaHourlyFixtureHasPredictionsKey() throws {
        let payload = try JSONDecoder().decode(NOAAPredictions.self, from: AlmanacFixtureLoader.data("NOAA/san-francisco-hourly.json"))
        #expect(payload.predictions.count == 48) // two GMT calendar days
        #expect(payload.predictions.allSatisfy { $0.type == nil })
    }

    @Test func noaaHiloFixtureHasTypedHighLowPredictions() throws {
        let payload = try JSONDecoder().decode(NOAAPredictions.self, from: AlmanacFixtureLoader.data("NOAA/san-francisco-hilo.json"))
        #expect(!payload.predictions.isEmpty)
        #expect(payload.predictions.contains { $0.type == "H" })
        #expect(payload.predictions.contains { $0.type == "L" })
    }

    // MARK: - JMA shape

    @Test func jmaAnnualFileHasDocumented136ByteRecords() throws {
        let data = try AlmanacFixtureLoader.data("JMA/tokyo-2026.txt")
        var widths: Set<Int> = []
        var recordCount = 0
        var index = data.startIndex
        while let newline = data[index...].firstIndex(of: UInt8(ascii: "\n")) {
            widths.insert(newline - index)
            recordCount += 1
            index = data.index(after: newline)
        }
        #expect(widths == [136])
        #expect(recordCount == 365)
    }

    @Test func jmaStationAuditRowContainsTokyoStation() throws {
        let text = try #require(String(data: AlmanacFixtureLoader.data("JMA/tokyo-station.txt"), encoding: .utf8))
        let cells = text.split(separator: "\n").first?
            .split(separator: "\t", omittingEmptySubsequences: false) ?? []
        #expect(cells.count > 2)
        #expect(cells[1] == "TK")
        #expect(cells[2] == "東京")
    }

    // MARK: - HKO shape

    /// HKO annual CSVs start with a UTF-8 BOM.
    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
    }

    @Test func hkoHourlyFixtureContainsCapturedHeader() throws {
        let text = Self.stripBOM(try #require(String(data: AlmanacFixtureLoader.data("HKO/tai-po-kau-2026-hourly.csv"), encoding: .utf8)))
        let header = text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(header == "MM,DD,01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24")
    }

    @Test func hkoHiloFixtureContainsCapturedHeader() throws {
        let text = Self.stripBOM(try #require(String(data: AlmanacFixtureLoader.data("HKO/tai-po-kau-2026-hilo.csv"), encoding: .utf8)))
        let header = text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(header == "Month,Date,Time,Height(m),Time,Height(m),Time,Height(m),Time,Height(m)")
        let rows = text.split(separator: "\n").dropFirst()
        #expect(rows.count == 16)
        #expect(rows.contains { $0.hasSuffix(",,") })
    }
}
