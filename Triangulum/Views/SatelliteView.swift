//
//  SatelliteView.swift
//  Triangulum
//
//  Widget displaying satellite tracking information and next ISS pass
//

import SwiftUI

struct SatelliteView: View {
    @ObservedObject var satelliteManager: SatelliteManager
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Satellite Tracker")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()

                if satelliteManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if !satelliteManager.isAvailable {
                unavailableView
            } else {
                contentView
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.white, Color.prussianSoft.opacity(0.3)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onReceive(timer) { time in
            currentTime = time
        }
    }

    // MARK: - Content Views

    private var unavailableView: some View {
        VStack(spacing: 8) {
            if satelliteManager.isLoading {
                Text("Fetching satellite data...")
                    .font(.subheadline)
                    .foregroundColor(.prussianBlueLight)
            } else {
                Text(satelliteManager.errorMessage.isEmpty ?
                     "Satellite data unavailable" : satelliteManager.errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.prussianError)

                Button("Retry") {
                    satelliteManager.forceRefreshTLEs()
                }
                .font(.caption)
                .foregroundColor(.prussianAccent)
            }
        }
    }

    private var contentView: some View {
        VStack(spacing: 12) {
            // Next ISS Pass Section
            if let nextPass = satelliteManager.nextISSPass {
                nextPassView(pass: nextPass)
            } else {
                Text("Calculating next ISS pass...")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            }

            Divider()

            // Satellite Positions
            satelliteListView
        }
    }

    private func nextPassView(pass: SatellitePass) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "airplane")
                    .foregroundColor(.prussianAccent)
                Text("Next ISS Pass")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }

            // Countdown or pass time
            let timeUntilRise = pass.riseTime.timeIntervalSince(currentTime)

            if timeUntilRise > 0 {
                // Upcoming pass
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rises in")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text(formatTimeInterval(timeUntilRise))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.prussianBlueDark)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Max Elevation")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text("\(Int(pass.maxAltitudeDeg))°")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.prussianAccent)
                    }
                }

                // Pass details
                HStack(spacing: 16) {
                    passDetailItem(title: "Rise", value: formatTime(pass.riseTime),
                                   direction: compassDirection(pass.riseAzimuthDeg))
                    passDetailItem(title: "Peak", value: formatTime(pass.peakTime), direction: nil)
                    passDetailItem(title: "Set", value: formatTime(pass.setTime),
                                   direction: compassDirection(pass.setAzimuthDeg))
                }
                .padding(.top, 4)
            } else if currentTime < pass.setTime {
                // Currently visible
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.green)
                    Text("ISS is visible now!")
                        .font(.headline)
                        .foregroundColor(.green)
                    Spacer()
                    Text("Sets in \(formatTimeInterval(pass.setTime.timeIntervalSince(currentTime)))")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundColor(.prussianBlueLight)
                    Text("Pass ended")
                        .font(.headline)
                        .foregroundColor(.prussianBlueLight)
                    Spacer()
                }
                .padding(8)
                .background(Color.prussianSoft.opacity(0.2))
                .cornerRadius(8)
            }
        }
    }

    private func passDetailItem(title: String, value: String, direction: String?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.prussianBlueLight)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.prussianBlueDark)
            if let dir = direction {
                Text(dir)
                    .font(.caption2)
                    .foregroundColor(.prussianBlueLight)
            }
        }
    }

    private var satelliteListView: some View {
        VStack(spacing: 8) {
            ForEach(satelliteManager.satellites) { satellite in
                satelliteRow(satellite: satellite)
            }
        }
    }

    private func satelliteRow(satellite: Satellite) -> some View {
        HStack {
            // Satellite icon with visibility indicator
            Circle()
                .fill(satellite.currentPosition?.isVisible == true ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(satellite.name)
                .font(.subheadline)
                .foregroundColor(.prussianBlueDark)
                .lineLimit(1)

            Spacer()

            if let position = satellite.currentPosition {
                if let elevation = position.altitudeDeg, let azimuth = position.azimuthDeg {
                    // Show Az/El for topocentric view
                    HStack(spacing: 12) {
                        Text("Az: \(Int(azimuth))°")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text("El: \(Int(elevation))°")
                            .font(.caption)
                            .foregroundColor(elevation > 0 ? .prussianAccent : .prussianBlueLight)
                    }
                } else {
                    // Show lat/lon for ground track
                    Text(String(format: "%.1f°, %.1f°", position.latitude, position.longitude))
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }
            } else if satellite.tle == nil {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.prussianError)
            } else {
                Text("Calculating...")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func compassDirection(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
        let clampedDegrees = normalizedDegrees < 0 ? normalizedDegrees + 360 : normalizedDegrees
        let index = Int((clampedDegrees + 22.5) / 45.0) % 8
        return directions[index]
    }
}

#Preview {
    SatelliteView(satelliteManager: SatelliteManager(locationManager: LocationManager()))
        .padding()
}
