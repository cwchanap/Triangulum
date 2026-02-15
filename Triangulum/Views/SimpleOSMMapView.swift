//
//  SimpleOSMMapView.swift
//  Triangulum
//
//  Created by Rovo Dev on 5/8/2025.
//

import SwiftUI
import MapKit
import os

struct SimpleOSMMapView: UIViewRepresentable {
    var center: CLLocationCoordinate2D
    var span: MKCoordinateSpan
    var enableCaching: Bool = false
    // Recenter token triggers animated recenter to `center` whenever it changes
    var recenterToken: UUID = UUID()
    var annotationCoordinate: CLLocationCoordinate2D?
    var annotationTitle: String?
    var annotationSubtitle: String?
    var onRegionChanged: ((MKCoordinateRegion) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()

        // Configure the map
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .standard

        // Set initial region
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: false)

        // Add OSM tile overlay
        setupOSMTileOverlay(on: mapView)

        // Add initial annotation if provided
        if let annotationCoordinate {
            let pin = MKPointAnnotation()
            pin.coordinate = annotationCoordinate
            pin.title = annotationTitle
            pin.subtitle = annotationSubtitle
            mapView.addAnnotation(pin)
        }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Recenter only when the token changes to avoid fighting user pans/zooms
        if context.coordinator.lastRecenterToken != recenterToken {
            context.coordinator.lastRecenterToken = recenterToken
            let newRegion = MKCoordinateRegion(center: center, span: span)
            uiView.setRegion(newRegion, animated: true)
        }

        // Update annotations to reflect selection state
        updateAnnotations(on: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func setupOSMTileOverlay(on mapView: MKMapView) {
        // Use the reliable tile server
        let osmTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"

        let tileOverlay: MKTileOverlay
        if enableCaching {
            // Use cached tile overlay
            tileOverlay = CachedTileOverlay(urlTemplate: osmTemplate)
            Logger.map.debug("SimpleOSMMapView: Added CACHED OSM tile overlay")
        } else {
            // Use standard tile overlay
            tileOverlay = MKTileOverlay(urlTemplate: osmTemplate)
            Logger.map.debug("SimpleOSMMapView: Added standard OSM tile overlay")
        }

        // Configure overlay with more permissive settings
        tileOverlay.canReplaceMapContent = true
        tileOverlay.maximumZ = 18
        tileOverlay.minimumZ = 0

        // Add to map
        mapView.addOverlay(tileOverlay)

        // Add a visual indicator that we're loading OSM
        addLoadingIndicator(to: mapView)
    }

    private func addLoadingIndicator(to mapView: MKMapView) {
        let label = UILabel()
        label.text = "Loading OpenStreetMap..."
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textColor = .systemBlue
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 999 // For easy removal later

        mapView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            label.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 20),
            label.widthAnchor.constraint(equalToConstant: 200),
            label.heightAnchor.constraint(equalToConstant: 30)
        ])

        // Remove after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            label.removeFromSuperview()
        }
    }

    private func regionsEqual(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        let threshold = 1e-6
        return abs(lhs.center.latitude - rhs.center.latitude) < threshold &&
            abs(lhs.center.longitude - rhs.center.longitude) < threshold &&
            abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < threshold &&
            abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < threshold
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: SimpleOSMMapView
        var lastRecenterToken: UUID?

        init(parent: SimpleOSMMapView) {
            self.parent = parent
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let cachedTileOverlay = overlay as? CachedTileOverlay {
                let renderer = CachedTileOverlayRenderer(tileOverlay: cachedTileOverlay)
                Logger.map.debug("SimpleOSMMapView: Creating CACHED tile renderer")
                return renderer
            } else if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                Logger.map.debug("SimpleOSMMapView: Creating standard tile renderer")
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            Logger.map.debug("SimpleOSMMapView: Map finished loading")
        }

        func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: Error) {
            Logger.map.error("SimpleOSMMapView: Failed to locate user: \(error.localizedDescription)")
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChanged?(mapView.region)
        }
    }

    // MARK: - Annotations
    private func updateAnnotations(on mapView: MKMapView) {
        // Remove existing non-user annotations
        let toRemove = mapView.annotations.filter { !($0 is MKUserLocation) }
        if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }

        // Add new annotation if available
        if let annotationCoordinate {
            let pin = MKPointAnnotation()
            pin.coordinate = annotationCoordinate
            pin.title = annotationTitle
            pin.subtitle = annotationSubtitle
            mapView.addAnnotation(pin)
        }
    }
}

#Preview {
    SimpleOSMMapView(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01),
        enableCaching: false,
        recenterToken: UUID()
    )
}
