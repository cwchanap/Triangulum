import SwiftUI
import CoreLocation

struct LocationView: View {
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "location")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Location")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()

                NavigationLink(destination: MapView(locationManager: locationManager)) {
                    Image(systemName: "map")
                        .font(.title3)
                        .foregroundColor(.prussianAccent)
                }
            }

            if !locationManager.isAvailable {
                Text("Location services disabled in system settings")
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                VStack(spacing: 8) {
                    Text("Location access denied")
                        .foregroundColor(.prussianError)
                        .font(.caption)
                    Button("Grant Permission") {
                        locationManager.requestLocationPermission()
                    }
                    .font(.caption)
                    .foregroundColor(.prussianAccent)
                }
            } else if locationManager.authorizationStatus == .notDetermined {
                VStack(spacing: 8) {
                    Text("Requesting location permission...")
                        .foregroundColor(.prussianBlueLight)
                        .font(.caption)
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.prussianAccent)
                }
            } else if !locationManager.errorMessage.isEmpty {
                Text(locationManager.errorMessage)
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Latitude")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(locationManager.latitude, specifier: "%.6f")°")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Longitude")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(locationManager.longitude, specifier: "%.6f")°")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Altitude (above sea level)")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(locationManager.altitude, specifier: "%.2f") m")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Accuracy")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(locationManager.accuracy, specifier: "%.1f") m")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(accuracyColor)
                        }
                    }

                    ProgressView(value: min(max((100 - locationManager.accuracy) / 100.0, 0.0), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: accuracyColor))
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.white, Color.prussianSoft]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .shadow(color: Color.prussianBlue.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private var accuracyColor: Color {
        if locationManager.accuracy < 5.0 {
            return .prussianSuccess
        } else if locationManager.accuracy < 20.0 {
            return .prussianAccent
        } else {
            return .prussianError
        }
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
