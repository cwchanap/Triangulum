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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            InstrumentHeader(icon: "antenna.radiowaves.left.and.right",
                             title: "Satellite Tracker", tint: .celCyan) {
                if satelliteManager.isLoading {
                    ProgressView().scaleEffect(0.7).tint(.celCyan)
                }
            }

            if !satelliteManager.isAvailable {
                unavailableView
            } else {
                contentView
            }
        }
        .widgetCard()
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
                    .foregroundColor(.celTextDim)
            } else {
                Text(satelliteManager.errorMessage.isEmpty ?
                     "Satellite data unavailable" : satelliteManager.errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.celRed)

                Button("Retry") {
                    satelliteManager.forceRefreshTLEs()
                }
                .font(.caption)
                .foregroundColor(.celCyan)
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
                    .foregroundColor(.celTextDim)
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
                    .foregroundColor(.celCyan)
                Text("Next ISS Pass")
                    .font(.headline)
                    .foregroundColor(.celText)
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
                            .foregroundColor(.celTextDim)
                        Text(formatTimeInterval(timeUntilRise))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.celText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Max Elevation")
                            .font(.caption)
                            .foregroundColor(.celTextDim)
                        Text("\(Int(pass.maxAltitudeDeg))°")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.celCyan)
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
                        .foregroundColor(.celGreen)
                    Text("ISS is visible now!")
                        .font(.headline)
                        .foregroundColor(.celGreen)
                    Spacer()
                    Text("Sets in \(formatTimeInterval(pass.setTime.timeIntervalSince(currentTime)))")
                        .font(.caption)
                        .foregroundColor(.celTextDim)
                }
                .padding(8)
                .background(Color.celGreen.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundColor(.celTextDim)
                    Text("Pass ended")
                        .font(.headline)
                        .foregroundColor(.celTextDim)
                    Spacer()
                }
                .padding(8)
                .background(Color.celSurfaceRaised.opacity(0.2))
                .cornerRadius(8)
            }
        }
    }

    private func passDetailItem(title: String, value: String, direction: String?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.celTextDim)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.celText)
            if let dir = direction {
                Text(dir)
                    .font(.caption2)
                    .foregroundColor(.celTextDim)
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
                .fill(satellite.currentPosition?.isVisible == true ? Color.celGreen : Color.celTextFaint.opacity(0.4))
                .frame(width: 8, height: 8)

            Text(satellite.name)
                .font(.subheadline)
                .foregroundColor(.celText)
                .lineLimit(1)

            Spacer()

            if let position = satellite.currentPosition {
                if let elevation = position.altitudeDeg, let azimuth = position.azimuthDeg {
                    // Show Az/El for topocentric view
                    HStack(spacing: 12) {
                        Text("Az: \(Int(azimuth))°")
                            .font(.caption)
                            .foregroundColor(.celTextDim)
                        Text("El: \(Int(elevation))°")
                            .font(.caption)
                            .foregroundColor(elevation > 0 ? .celCyan : .celTextDim)
                    }
                } else {
                    // Show lat/lon for ground track
                    Text(String(format: "%.1f°, %.1f°", position.latitude, position.longitude))
                        .font(.caption)
                        .foregroundColor(.celTextDim)
                }
            } else if satellite.tle == nil {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.celRed)
            } else {
                Text("Calculating...")
                    .font(.caption)
                    .foregroundColor(.celTextDim)
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
        Self.timeFormatter.string(from: date)
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
