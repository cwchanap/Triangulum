//
//  TideProvider.swift
//  Triangulum
//

/// Closed set of official tide prediction sources supported by the Almanac tab.
///
/// `enabled` is only the production default: `TideCoverageResolver`,
/// `TideService`, and `AlmanacDependencies.live()` must consume the same
/// injected set so disabled-provider behavior stays directly testable.
///
/// Supported-but-disabled providers stay in the enum so they remain
/// distinguishable from unsupported geography; source contracts are recorded
/// in `docs/almanac-tide-source-contracts.md`.
enum TideProvider: String, CaseIterable, Codable, Hashable {
    case canadaCHS
    case unitedStatesNOAA
    case japanJMA
    case hongKongHKO

    static let enabled: Set<Self> = [
        .canadaCHS,
        .unitedStatesNOAA,
        .japanJMA,
        .hongKongHKO
    ]

    var attribution: String {
        switch self {
        case .canadaCHS: "Canadian Hydrographic Service"
        case .unitedStatesNOAA: "NOAA CO-OPS"
        case .japanJMA: "Japan Meteorological Agency"
        case .hongKongHKO: "Hong Kong Observatory"
        }
    }
}
