import SwiftUI

struct CompassPageView: View {
    @ObservedObject var locationManager: LocationManager
    @AppStorage("nightVisionMode") private var nightVisionMode = false
    @State private var isCalibrating = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if nightVisionMode {
                Color.black.ignoresSafeArea()
            } else {
                StarfieldBackground(showConstellation: false)
            }
            VStack(spacing: 24) {
                Spacer()
                CompassView(
                    heading: locationManager.heading,
                    redMode: nightVisionMode,
                    tint: nightVisionMode ? .red : .celText
                )
                    .frame(width: 260, height: 260)
                Text("\(Int(locationManager.heading.rounded()))°")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(nightVisionMode ? .red : .celText)
                Spacer()
            }
        }
        .navigationTitle("Compass")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.celBackgroundTop, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    locationManager.requestHeadingCalibration()
                } label: {
                    Image(systemName: "scope")
                        .foregroundColor(.white)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    CompassPageView(locationManager: LocationManager())
}
