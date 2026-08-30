import SwiftUI

enum ProductTab: Hashable {
    case live
    case field
    case footprint
    case settings

    var title: String {
        switch self {
        case .live: "Live"
        case .field: "Field"
        case .footprint: "Footprint"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .live: "waveform.path.ecg"
        case .field: "map"
        case .footprint: "square.stack.3d.up"
        case .settings: "gearshape"
        }
    }
}

struct FieldHubView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var satelliteManager: SatelliteManager
    @State private var selectedMode: FieldMode = .map

    var body: some View {
        VStack(spacing: 0) {
            Picker("Field mode", selection: $selectedMode) {
                ForEach(FieldMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, CelSpace.md)
            .padding(.vertical, CelSpace.sm)

            fieldContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(StarfieldBackground(showConstellation: false))
        .navigationTitle("Field")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.celBackgroundTop.opacity(0.85), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private var fieldContent: some View {
        switch selectedMode {
        case .map:
            MapView(locationManager: locationManager)
        case .compass:
            CompassPageView(locationManager: locationManager)
        case .sky:
            ConstellationMapView(locationManager: locationManager,
                                 satelliteManager: satelliteManager)
        }
    }
}

private enum FieldMode: CaseIterable, Identifiable {
    case map
    case compass
    case sky

    var id: Self { self }

    var title: String {
        switch self {
        case .map: "Map"
        case .compass: "Compass"
        case .sky: "Sky"
        }
    }
}
