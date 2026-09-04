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

    /// Production default. All four providers are enabled: NOAA, JMA, and HKO
    /// unconditionally; CHS is enabled because Triangulum is distributed free
    /// of charge for non-commercial use, which satisfies the CHS website
    /// licence agreement's prohibition on derivative products made for sale
    /// or profit (see `docs/almanac-tide-source-contracts.md`). The required
    /// derivative-product notice is carried in `attributionNotice` and
    /// displayed on the tide station card. If distribution ever becomes
    /// commercial, remove `.canadaCHS` here and Canada coverage will report
    /// `.providerUnavailable` without any further change.
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

    /// The source's required derivative-product notice (wording recorded in
    /// `docs/almanac-tide-source-contracts.md`), shown on the tide station
    /// card alongside `attribution`. Nil when source acknowledgment alone
    /// satisfies the contract (NOAA data is U.S. public domain).
    var attributionNotice: String? {
        switch self {
        case .canadaCHS:
            "This product is not to be used for navigation. This product was made by or for Triangulum "
                + "and contains intellectual property (Data) of the Canadian Hydrographic Service of the "
                + "Department of Fisheries and Oceans. The copyrights in the Data are and remain the "
                + "property of His Majesty the King in Right of Canada and shall not be sold, licensed, "
                + "leased, assigned or given to a third party. The incorporation of the Data in this "
                + "product does not constitute an endorsement or an approval of this product by the "
                + "Canadian Hydrographic Service, the Department of Fisheries and Oceans or His Majesty "
                + "the King in Right of Canada."
        case .unitedStatesNOAA:
            nil
        case .japanJMA:
            "Source: Japan Meteorological Agency website "
                + "(https://ds.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/readme.html). "
                + "The predictions are edited and processed for display in this app and are not "
                + "presented as if created by the Government of Japan."
        case .hongKongHKO:
            "Source: tide data of the Hong Kong Observatory, a department of the Government of the "
                + "Hong Kong Special Administrative Region, obtained through DATA.GOV.HK "
                + "(https://data.gov.hk). The Government of the HKSAR and the Hong Kong Observatory "
                + "own the intellectual property rights in the data and all copies."
        }
    }
}
