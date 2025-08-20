import SwiftUI
import MapKit

struct OSMMapView: UIViewRepresentable {
    var center: CLLocationCoordinate2D
    var span: MKCoordinateSpan
    var isTrackingUser: Bool

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)

        // Configure OpenStreetMap tile overlay (basic, no caching)
        // Using alternative tile server that might be more reliable
        let template = "https://a.tile.openstreetmap.org/{z}/{x}/{y}.png"
        let overlay = MKTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = true
        overlay.maximumZ = 19
        overlay.minimumZ = 0
        
        // Add debugging
        print("OSMMapView: Adding tile overlay with template: \(template)")
        
        mapView.addOverlay(overlay, level: .aboveLabels)

        mapView.showsUserLocation = true
        mapView.userTrackingMode = isTrackingUser ? .follow : .none
        mapView.delegate = context.coordinator

        // Initial region
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: false)

        // Add unobtrusive OSM attribution per tile policy
        addOSMAttributionOverlay(to: mapView)

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
            print("OSMMapView: rendererFor overlay called: \(type(of: overlay))")
            if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                print("OSMMapView: Created tile overlay renderer")
                return renderer
            }
            print("OSMMapView: Using default overlay renderer")
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            print("OSMMapView: Region changed to: \(mapView.region)")
        }
    }

    private func regionsEqual(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        let latDelta = abs(lhs.center.latitude - rhs.center.latitude)
        let lonDelta = abs(lhs.center.longitude - rhs.center.longitude)
        let spanLatDelta = abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta)
        let spanLonDelta = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
        return latDelta < 1e-6 && lonDelta < 1e-6 && spanLatDelta < 1e-6 && spanLonDelta < 1e-6
    }

    // MARK: - OSM Attribution
    private func addOSMAttributionOverlay(to mapView: MKMapView) {
        // Avoid duplicating if called more than once
        if mapView.viewWithTag(1001) != nil { return }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.clipsToBounds = true
        blur.layer.cornerRadius = 8
        blur.tag = 1001 // sentinel to find later if needed

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "© OpenStreetMap contributors"
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)

        blur.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -4)
        ])

        mapView.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.trailingAnchor.constraint(equalTo: mapView.layoutMarginsGuide.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.bottomAnchor, constant: -4)
        ])

        // Tapping the attribution opens OSM copyright page
        let tap = UITapGestureRecognizer(target: contextTarget(), action: #selector(OSMAttributionOpener.openOSMCopyright))
        blur.addGestureRecognizer(tap)
        blur.isUserInteractionEnabled = true
        label.isUserInteractionEnabled = true
    }

    private func contextTarget() -> OSMAttributionOpener {
        OSMAttributionOpener.shared
    }
}

// Helper singleton to handle link opening without retaining cycles
final class OSMAttributionOpener: NSObject {
    static let shared = OSMAttributionOpener()
    private override init() {}

    @objc func openOSMCopyright() {
        guard let url = URL(string: "https://www.openstreetmap.org/copyright") else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}
