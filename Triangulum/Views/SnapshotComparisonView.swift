import SwiftUI
import MapKit
import CoreLocation

struct SnapshotComparisonView: View {
    let snapshot1: SensorSnapshot
    let snapshot2: SensorSnapshot
    @Environment(\.dismiss) private var dismiss

    private var distance: CLLocationDistance {
        let loc1 = CLLocation(latitude: snapshot1.location.latitude, longitude: snapshot1.location.longitude)
        let loc2 = CLLocation(latitude: snapshot2.location.latitude, longitude: snapshot2.location.longitude)
        return loc1.distance(from: loc2)
    }

    private var timeDifference: TimeInterval {
        abs(snapshot2.timestamp.timeIntervalSince(snapshot1.timestamp))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Map with both locations
                    comparisonMapCard

                    // Time comparison
                    timeComparisonCard

                    // Barometer comparison
                    barometerComparisonCard

                    // Location comparison
                    locationComparisonCard

                    // Weather comparison (if available for both)
                    if snapshot1.weather != nil && snapshot2.weather != nil {
                        weatherComparisonCard
                    }
                }
                .padding()
            }
            .background(Color.prussianSoft.opacity(0.3))
            .navigationTitle("Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.prussianAccent)
                }
            }
        }
    }

    // MARK: - Map Card

    private var comparisonMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map")
                    .foregroundColor(.prussianAccent)
                Text("Locations")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                Text(formattedDistance)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.prussianAccent)
            }

            ComparisonMapView(
                location1: CLLocationCoordinate2D(
                    latitude: snapshot1.location.latitude,
                    longitude: snapshot1.location.longitude
                ),
                location2: CLLocationCoordinate2D(
                    latitude: snapshot2.location.latitude,
                    longitude: snapshot2.location.longitude
                )
            )
            .frame(height: 200)
            .cornerRadius(12)

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.prussianAccent)
                        .frame(width: 10, height: 10)
                    Text("Snapshot 1")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.prussianWarning)
                        .frame(width: 10, height: 10)
                    Text("Snapshot 2")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }
                Spacer()
            }
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Time Comparison Card

    private var timeComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.prussianAccent)
                Text("Time")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                Text(formattedTimeDifference)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.prussianBlueLight)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snapshot 1")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(snapshot1.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.prussianBlueDark)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Snapshot 2")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(snapshot2.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.prussianBlueDark)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Barometer Comparison Card

    private var barometerComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "barometer")
                    .foregroundColor(.prussianAccent)
                Text("Barometer")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }

            ComparisonRow(
                label: "Pressure",
                value1: String(format: "%.2f kPa", snapshot1.barometer.pressure),
                value2: String(format: "%.2f kPa", snapshot2.barometer.pressure),
                delta: snapshot2.barometer.pressure - snapshot1.barometer.pressure,
                unit: "kPa",
                precision: 2
            )

            ComparisonRow(
                label: "Sea Level",
                value1: seaLevelPressureText(for: snapshot1),
                value2: seaLevelPressureText(for: snapshot2),
                delta: seaLevelPressureDelta,
                unit: "kPa",
                precision: 2
            )
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Location Comparison Card

    private var locationComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location")
                    .foregroundColor(.prussianAccent)
                Text("Location")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }

            ComparisonRow(
                label: "Latitude",
                value1: String(format: "%.5f°", snapshot1.location.latitude),
                value2: String(format: "%.5f°", snapshot2.location.latitude),
                delta: snapshot2.location.latitude - snapshot1.location.latitude,
                unit: "°",
                precision: 5
            )

            ComparisonRow(
                label: "Longitude",
                value1: String(format: "%.5f°", snapshot1.location.longitude),
                value2: String(format: "%.5f°", snapshot2.location.longitude),
                delta: snapshot2.location.longitude - snapshot1.location.longitude,
                unit: "°",
                precision: 5
            )

            ComparisonRow(
                label: "Altitude",
                value1: String(format: "%.1f m", snapshot1.location.altitude),
                value2: String(format: "%.1f m", snapshot2.location.altitude),
                delta: snapshot2.location.altitude - snapshot1.location.altitude,
                unit: "m",
                precision: 1
            )

            ComparisonRow(
                label: "Accuracy",
                value1: String(format: "±%.1f m", snapshot1.location.accuracy),
                value2: String(format: "±%.1f m", snapshot2.location.accuracy),
                delta: snapshot2.location.accuracy - snapshot1.location.accuracy,
                unit: "m",
                precision: 1
            )
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Weather Comparison Card

    private var weatherComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cloud.sun")
                    .foregroundColor(.prussianAccent)
                Text("Weather")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }

            if let weather1 = snapshot1.weather, let weather2 = snapshot2.weather {
                ComparisonRow(
                    label: "Temperature",
                    value1: String(format: "%.1f°C", weather1.temperature),
                    value2: String(format: "%.1f°C", weather2.temperature),
                    delta: weather2.temperature - weather1.temperature,
                    unit: "°C",
                    precision: 1
                )

                ComparisonRow(
                    label: "Humidity",
                    value1: "\(weather1.humidity)%",
                    value2: "\(weather2.humidity)%",
                    delta: Double(weather2.humidity - weather1.humidity),
                    unit: "%",
                    precision: 0
                )

                HStack {
                    Text("Conditions")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Spacer()
                    Text(weather1.condition)
                        .font(.caption)
                        .foregroundColor(.prussianBlueDark)
                    Text("→")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(weather2.condition)
                        .font(.caption)
                        .foregroundColor(.prussianBlueDark)
                }
            } else {
                Text("Weather data not available for one or both snapshots")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
                    .italic()
            }
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Color.white, Color.prussianSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.prussianBlue.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var formattedDistance: String {
        if distance < 1000 {
            return String(format: "%.0f m apart", distance)
        } else {
            return String(format: "%.2f km apart", distance / 1000)
        }
    }

    private var formattedTimeDifference: String {
        let hours = Int(timeDifference / 3600)
        let minutes = Int((timeDifference.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s") apart"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m apart"
        } else {
            return "\(minutes) min apart"
        }
    }

    private var seaLevelPressureDelta: Double? {
        guard let pressure1 = snapshot1.barometer.seaLevelPressure,
              let pressure2 = snapshot2.barometer.seaLevelPressure else {
            return nil
        }
        return pressure2 - pressure1
    }

    private func seaLevelPressureText(for snapshot: SensorSnapshot) -> String {
        guard let seaLevelPressure = snapshot.barometer.seaLevelPressure else {
            return "--"
        }
        return String(format: "%.2f kPa", seaLevelPressure)
    }
}

// MARK: - Comparison Row

struct ComparisonRow: View {
    let label: String
    let value1: String
    let value2: String
    let delta: Double?
    let unit: String
    let precision: Int

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
                Spacer()
                deltaView
            }

            HStack {
                Text(value1)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.prussianBlueDark)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)

                Text(value2)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.prussianBlueDark)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var deltaView: some View {
        if let delta {
            let sign = delta >= 0 ? "+" : ""
            let formattedDelta = String(format: "%@%.\(precision)f %@", sign, delta, unit)
            let color: Color = delta > 0 ? .prussianSuccess : (delta < 0 ? .prussianWarning : .prussianBlueLight)

            Text(formattedDelta)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.1))
                .cornerRadius(4)
        } else {
            Text("--")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.prussianBlueLight)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.prussianBlueLight.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

// MARK: - Comparison Map View

struct ComparisonMapView: UIViewRepresentable {
    let location1: CLLocationCoordinate2D
    let location2: CLLocationCoordinate2D

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        // Add annotations
        let annotation1 = ComparisonAnnotation(
            coordinate: location1,
            title: "Snapshot 1",
            isFirst: true
        )
        let annotation2 = ComparisonAnnotation(
            coordinate: location2,
            title: "Snapshot 2",
            isFirst: false
        )
        mapView.addAnnotations([annotation1, annotation2])

        // Add line between points
        let coordinates = [location1, location2]
        let polyline = MKPolyline(coordinates: coordinates, count: 2)
        mapView.addOverlay(polyline)

        // Fit both annotations
        let annotations = [annotation1, annotation2]
        let rect = annotations.reduce(MKMapRect.null) { rect, annotation in
            let point = MKMapPoint(annotation.coordinate)
            let annotationRect = MKMapRect(x: point.x - 1000, y: point.y - 1000, width: 2000, height: 2000)
            return rect.union(annotationRect)
        }

        let padding = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let comparisonAnnotation = annotation as? ComparisonAnnotation else {
                return nil
            }

            let identifier = "ComparisonPin"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }

            view?.annotation = annotation
            view?.markerTintColor = comparisonAnnotation.isFirst ?
                UIColor(red: 0.26, green: 0.52, blue: 0.78, alpha: 1.0) :  // prussianAccent
                UIColor(red: 0.92, green: 0.49, blue: 0.13, alpha: 1.0)   // prussianWarning
            view?.glyphText = comparisonAnnotation.isFirst ? "1" : "2"
            view?.canShowCallout = true

            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.13, green: 0.35, blue: 0.55, alpha: 0.6)  // prussianBlueLight
                renderer.lineWidth = 2
                renderer.lineDashPattern = [5, 5]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Comparison Annotation

class ComparisonAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var isFirst: Bool

    init(coordinate: CLLocationCoordinate2D, title: String, isFirst: Bool) {
        self.coordinate = coordinate
        self.title = title
        self.isFirst = isFirst
    }
}

#Preview {
    let locationManager = LocationManager()
    let barometerManager = BarometerManager(locationManager: locationManager)

    let snapshot1 = SensorSnapshot(
        barometerManager: barometerManager,
        locationManager: locationManager,
        accelerometerManager: AccelerometerManager(),
        gyroscopeManager: GyroscopeManager(),
        magnetometerManager: MagnetometerManager(),
        weatherManager: nil
    )

    let snapshot2 = SensorSnapshot(
        barometerManager: barometerManager,
        locationManager: locationManager,
        accelerometerManager: AccelerometerManager(),
        gyroscopeManager: GyroscopeManager(),
        magnetometerManager: MagnetometerManager(),
        weatherManager: nil
    )

    return SnapshotComparisonView(
        snapshot1: snapshot1,
        snapshot2: snapshot2
    )
}
