import SwiftUI
import MapKit

struct OSMMapView: UIViewRepresentable {
    var center: CLLocationCoordinate2D
    var span: MKCoordinateSpan
    var isTrackingUser: Bool

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)

        // Configure OpenStreetMap tile overlay
        let template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        let overlay = MKTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = true
        mapView.addOverlay(overlay, level: .aboveLabels)

        mapView.showsUserLocation = true
        mapView.userTrackingMode = isTrackingUser ? .follow : .none
        mapView.delegate = context.coordinator

        // Initial region
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: false)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update tracking mode
        let desiredMode: MKUserTrackingMode = isTrackingUser ? .follow : .none
        if uiView.userTrackingMode != desiredMode {
            uiView.userTrackingMode = desiredMode
        }

        // Only recenter when tracking is on to avoid fighting user panning
        if isTrackingUser {
            let region = MKCoordinateRegion(center: center, span: span)
            if !regionsEqual(lhs: uiView.region, rhs: region) {
                uiView.setRegion(region, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }

    private func regionsEqual(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        let latDelta = abs(lhs.center.latitude - rhs.center.latitude)
        let lonDelta = abs(lhs.center.longitude - rhs.center.longitude)
        let spanLatDelta = abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta)
        let spanLonDelta = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
        return latDelta < 1e-6 && lonDelta < 1e-6 && spanLatDelta < 1e-6 && spanLonDelta < 1e-6
    }
}

