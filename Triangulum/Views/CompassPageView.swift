import SwiftUI

struct CompassPageView: View {
    @ObservedObject var locationManager: LocationManager
    @AppStorage("nightVisionMode") private var nightVisionMode = false
    @State private var isCalibrating = false

    var body: some View {
        ZStack {
            (nightVisionMode ? Color.black : Color.prussianSoft).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                CompassView(heading: locationManager.heading, redMode: nightVisionMode)
                    .frame(width: 260, height: 260)
                Text("\(Int(locationManager.heading.rounded()))°")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(nightVisionMode ? .red : .prussianBlueDark)
                Spacer()
            }
        }
        .navigationTitle("Compass")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.prussianBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    CompassPageView(locationManager: LocationManager())
}

