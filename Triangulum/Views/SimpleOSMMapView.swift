//
//  SimpleOSMMapView.swift
//  Triangulum
//
//  Created by Rovo Dev on 5/8/2025.
//

import SwiftUI
import MapKit

struct SimpleOSMMapView: UIViewRepresentable {
    var center: CLLocationCoordinate2D
    var span: MKCoordinateSpan
    var enableCaching: Bool = false
    var shouldCenterOnUser: Bool = false
    
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
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Only update region when explicitly requested via shouldCenterOnUser
        if shouldCenterOnUser {
            let newRegion = MKCoordinateRegion(center: center, span: span)
            uiView.setRegion(newRegion, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func setupOSMTileOverlay(on mapView: MKMapView) {
        // Use the reliable tile server
        let osmTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        
        let tileOverlay: MKTileOverlay
        if enableCaching {
            // Use cached tile overlay
            tileOverlay = CachedTileOverlay(urlTemplate: osmTemplate)
            print("SimpleOSMMapView: Added CACHED OSM tile overlay")
        } else {
            // Use standard tile overlay
            tileOverlay = MKTileOverlay(urlTemplate: osmTemplate)
            print("SimpleOSMMapView: Added standard OSM tile overlay")
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
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let cachedTileOverlay = overlay as? CachedTileOverlay {
                let renderer = CachedTileOverlayRenderer(tileOverlay: cachedTileOverlay)
                print("SimpleOSMMapView: Creating CACHED tile renderer")
                return renderer
            } else if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                print("SimpleOSMMapView: Creating standard tile renderer")
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            print("SimpleOSMMapView: Map finished loading")
        }
        
        func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: Error) {
            print("SimpleOSMMapView: Failed to locate user: \(error)")
        }
    }
}

#Preview {
    SimpleOSMMapView(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
}