import SwiftUI
import CoreLocation

struct LocationView: View {
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        VStack(spacing: CelSpace.md) {
            InstrumentHeader(icon: "location.fill", title: "Location", tint: .celCyan) {
                NavigationLink(destination: MapView(locationManager: locationManager)) {
                    Image(systemName: "map")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.celCyan)
                }
            }

            if !locationManager.isAvailable {
                CelInlineMessage(text: "Location services disabled in system settings", color: .celRed)
            } else if locationManager.authorizationStatus == .denied ||
                        locationManager.authorizationStatus == .restricted {
                VStack(spacing: 8) {
                    CelInlineMessage(text: "Location access denied", color: .celRed)
                    // Once denied/restricted, requestWhenInUseAuthorization() is a
                    // system no-op, so guide the user to Settings to re-enable access.
                    Button("Open Settings") {
                        locationManager.openAppSettings()
                    }
                    .font(.celLabel)
                    .foregroundStyle(Color.celCyan)
                }
            } else if locationManager.authorizationStatus == .notDetermined {
                VStack(spacing: 8) {
                    ProgressView().tint(.celCyan)
                    Text("Acquiring fix…").celEyebrow()
                }
            } else if !locationManager.errorMessage.isEmpty {
                CelInlineMessage(text: locationManager.errorMessage, color: .celRed)
            } else {
                VStack(spacing: CelSpace.md) {
                    HStack(alignment: .top) {
                        MetricReadout("Latitude",
                                      value: String(format: "%.5f°", locationManager.latitude))
                        MetricReadout("Longitude",
                                      value: String(format: "%.5f°", locationManager.longitude),
                                      alignment: .trailing)
                    }

                    HStack(alignment: .top) {
                        MetricReadout("Altitude",
                                      value: String(format: "%.1f", locationManager.altitude),
                                      unit: "m")
                        MetricReadout("Accuracy",
                                      value: String(format: "±%.1f", locationManager.accuracy),
                                      unit: "m", alignment: .trailing, valueColor: accuracyColor)
                    }

                    VStack(spacing: 5) {
                        HStack {
                            Text("Fix Quality").celEyebrow()
                            Spacer()
                            StatusPill(accuracyLabel, color: accuracyColor)
                        }
                        LuminousBar(value: min(max((100 - locationManager.accuracy) / 100.0, 0.0), 1.0),
                                    tint: accuracyColor)
                    }
                }
            }
        }
        .widgetCard()
    }

    private var accuracyColor: Color {
        if locationManager.accuracy < 5.0 {
            return .celGreen
        } else if locationManager.accuracy < 20.0 {
            return .celCyan
        } else {
            return .celAmber
        }
    }

    private var accuracyLabel: String {
        if locationManager.accuracy < 5.0 { return "Precise" }
        if locationManager.accuracy < 20.0 { return "Good" }
        return "Coarse"
    }
}

#Preview {
    let manager = LocationManager()

    return LocationView(locationManager: manager)
        .onAppear {
            manager.latitude = 37.7749
            manager.longitude = -122.4194
            manager.altitude = 16.0
            manager.accuracy = 3.0
            manager.isAvailable = true
            manager.authorizationStatus = .authorizedWhenInUse
        }
        .padding()
}
