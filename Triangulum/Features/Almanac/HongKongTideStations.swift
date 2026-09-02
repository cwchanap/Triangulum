//
//  HongKongTideStations.swift
//  Triangulum
//

import Foundation

/// Compiled HKO tide-station catalogue: the intersection of the active
/// stations listed by the HHOT (hourly heights) and HLT (high/low times and
/// heights) datasets on data.gov.hk (verified 2026-09-01). The two closed
/// stations flagged by the dataset (Chi Ma Wan, closed 1997; Lok On Pai,
/// closed 1999) are excluded. Coordinates are the stations' geographic
/// positions, used only for nearest-station selection. No runtime resource
/// loading: annual CSVs are fetched per station/year/kind by
/// `HongKongTideClient`.

enum HongKongTideStations {

    private struct Entry {
        let code: String
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private static let entries: [Entry] = [
        .init(code: "QUB", name: "Quarry Bay", latitude: 22.2926000, longitude: 114.2219000),
        .init(code: "CCH", name: "Cheung Chau", latitude: 22.2072000, longitude: 114.0289000),
        .init(code: "WAG", name: "Waglan Island", latitude: 22.1820000, longitude: 114.3040000),
        .init(code: "TAO", name: "Tai O", latitude: 22.2541000, longitude: 113.8561000),
        .init(code: "TPK", name: "Tai Po Kau", latitude: 22.4700000, longitude: 114.2150000),
        .init(code: "KLW", name: "Ko Lau Wan", latitude: 22.5394000, longitude: 114.2489000),
        .init(code: "KCT", name: "Kwai Chung", latitude: 22.3519000, longitude: 114.1289000),
        .init(code: "MWC", name: "Ma Wan", latitude: 22.3528000, longitude: 114.0650000),
        .init(code: "SPW", name: "Shek Pik", latitude: 22.2211000, longitude: 113.8944000),
        .init(code: "TBT", name: "Tsim Bei Tsui", latitude: 22.4872000, longitude: 114.0550000),
        .init(code: "TMW", name: "Tai Miu Wan", latitude: 22.3086000, longitude: 114.2739000),
        .init(code: "CLK", name: "Chek Lap Kok", latitude: 22.2986000, longitude: 113.9306000)
    ]

    static let all: [TideStation] = entries.map { entry in
        TideStation(
            id: entry.code,
            provider: .hongKongHKO,
            providerStationCode: entry.code,
            name: entry.name,
            latitude: entry.latitude,
            longitude: entry.longitude,
            timeZoneIdentifier: "Asia/Hong_Kong",
            datumLabel: "Chart Datum",
            supportsHourlyCurve: true
        )
    }
}
