import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var locationManager: LocationManager
    @AppStorage("mapProvider") private var mapProvider = "apple" // "apple" or "osm"
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    @State private var isTrackingUser = false
    @State private var isCacheMode = false
    @State private var shouldCenterOSMOnUser = false
    @State private var cacheRadius: Double = 1000.0
    @State private var minZoom = 10
    @State private var maxZoom = 16
    @StateObject private var cacheManager = TileCacheManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "map")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Map")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                
                if mapProvider == "osm" {
                    Button(action: { isCacheMode.toggle() }) {
                        Image(systemName: isCacheMode ? "externaldrive.fill" : "externaldrive")
                            .font(.title3)
                            .foregroundColor(isCacheMode ? .prussianAccent : .prussianBlueLight)
                    }
                }
                
                Button(action: centerOnUser) {
                    Image(systemName: isTrackingUser ? "location.fill" : "location")
                        .font(.title3)
                        .foregroundColor(.prussianAccent)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Cache controls when in cache mode
            if isCacheMode && mapProvider == "osm" {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pan map to desired area, then tap 'Cache This Area'")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(cacheManager.getCacheInfo().sizeInMB, specifier: "%.1f") MB cached (\(cacheManager.tilesCount) tiles)")
                                .font(.caption2)
                                .foregroundColor(.prussianBlueLight.opacity(0.8))
                        }
                        Spacer()
                        if cacheManager.isDownloading {
                            VStack(spacing: 2) {
                                ProgressView(value: cacheManager.downloadProgress)
                                    .frame(width: 60)
                                    .tint(.prussianAccent)
                                Text("\(Int(cacheManager.downloadProgress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.prussianBlueDark)
                            }
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Radius: \(Int(cacheRadius))m")
                                .font(.caption2)
                                .foregroundColor(.prussianBlueDark)
                            Slider(value: $cacheRadius, in: 500...5000, step: 250)
                                .tint(.prussianAccent)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 4) {
                            Text("Zoom: \(minZoom)-\(maxZoom)")
                                .font(.caption2)
                                .foregroundColor(.prussianBlueDark)
                            HStack(spacing: 8) {
                                Picker("Min", selection: $minZoom) {
                                    ForEach(8...16, id: \.self) { Text("\($0)").tag($0) }
                                }.pickerStyle(.menu).font(.caption2)
                                Picker("Max", selection: $maxZoom) {
                                    ForEach(10...18, id: \.self) { Text("\($0)").tag($0) }
                                }.pickerStyle(.menu).font(.caption2)
                            }
                        }
                        
                        Button(action: {
                            Task {
                                await cacheManager.clearCache()
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.prussianError)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.prussianSoft.opacity(0.3))
            }
            
            if !locationManager.isAvailable {
                Text("Location services disabled in system settings")
                    .foregroundColor(.prussianError)
                    .font(.caption)
                    .frame(height: 200)
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
                .frame(height: 200)
            } else if locationManager.authorizationStatus == .notDetermined {
                VStack(spacing: 8) {
                    Text("Requesting location permission...")
                        .foregroundColor(.prussianBlueLight)
                        .font(.caption)
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.prussianAccent)
                }
                .frame(height: 200)
            } else if !locationManager.errorMessage.isEmpty {
                Text(locationManager.errorMessage)
                    .foregroundColor(.prussianError)
                    .font(.caption)
                    .frame(height: 200)
            } else {
                Group {
                    if mapProvider == "osm" {
                        // OpenStreetMap with optional caching
                        SimpleOSMMapView(
                            center: userLocation.latitude == 0.0 && userLocation.longitude == 0.0
                            ? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                            : userLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01),
                            enableCaching: isCacheMode,
                            shouldCenterOnUser: shouldCenterOSMOnUser
                        )
                        .overlay(
                            // Cache mode overlay
                            isCacheMode ? 
                            ZStack {
                                // Center crosshair to show cache center
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                            .font(.title)
                                            .foregroundColor(.blue.opacity(0.8))
                                            .background(Circle().fill(Color.white.opacity(0.8)).frame(width: 30, height: 30))
                                        Spacer()
                                    }
                                    Spacer()
                                }
                                
                                // Cache button at bottom
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Button(action: cacheCurrentArea) {
                                            HStack {
                                                Image(systemName: cacheManager.isDownloading ? "arrow.down.circle" : "arrow.down.circle.fill")
                                                Text(cacheManager.isDownloading ? "Downloading..." : "Cache This Area")
                                                    .fontWeight(.medium)
                                            }
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [.prussianAccent, .prussianBlue]),
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .cornerRadius(25)
                                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                        }
                                        .disabled(cacheManager.isDownloading)
                                        .opacity(cacheManager.isDownloading ? 0.6 : 1.0)
                                        Spacer()
                                    }
                                    .padding(.bottom, 20)
                                }
                                
                                // Radius indicator in top corner
                                VStack {
                                    HStack {
                                        Spacer()
                                        Text("⊕ \(Int(cacheRadius))m radius")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.8))
                                            .cornerRadius(12)
                                    }
                                    .padding(.top, 10)
                                    .padding(.trailing, 10)
                                    Spacer()
                                }
                            } : nil
                        )
                    } else {
                        // Apple Maps (SwiftUI Map)
                        Map(position: $position) {
                            UserAnnotation()

                            if userLocation.latitude != 0.0 || userLocation.longitude != 0.0 {
                                Annotation("Current Location", coordinate: userLocation) {
                                    Circle()
                                        .fill(Color.prussianAccent)
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.prussianBlue.opacity(0.2), lineWidth: 1)
                )
            }
            
            if locationManager.isAvailable && locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coordinates")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text("\(locationManager.latitude, specifier: "%.6f")°, \(locationManager.longitude, specifier: "%.6f")°")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.prussianBlueDark)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Accuracy")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text("\(locationManager.accuracy, specifier: "%.1f") m")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(accuracyColor)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .background(Color.white.opacity(0.9))
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
        .ignoresSafeArea(.all, edges: .bottom)
        .onChange(of: locationManager.latitude) { _, _ in
            updatePosition()
        }
        .onChange(of: locationManager.longitude) { _, _ in
            updatePosition()
        }
        .onChange(of: isCacheMode) { _, newValue in
            if newValue {
                cacheManager.updateCacheStats()
            }
        }
    }
    
    private var userLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: locationManager.latitude, longitude: locationManager.longitude)
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
    
    private func updatePosition() {
        guard locationManager.latitude != 0.0 || locationManager.longitude != 0.0 else { return }
        
        // Only auto-update position for Apple Maps, and only when tracking is enabled
        if isTrackingUser && mapProvider != "osm" {
            position = .region(
                MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }
    
    private func centerOnUser() {
        guard locationManager.latitude != 0.0 || locationManager.longitude != 0.0 else { return }
        
        if mapProvider == "osm" {
            // Trigger manual centering for OSM
            shouldCenterOSMOnUser = true
            DispatchQueue.main.async {
                shouldCenterOSMOnUser = false
            }
        } else {
            // Handle Apple Maps centering
            withAnimation(.easeInOut(duration: 1.0)) {
                position = .region(
                    MKCoordinateRegion(
                        center: userLocation,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                )
            }
        }
        
        isTrackingUser.toggle()
    }
    
    private func cacheCurrentArea() {
        let center = userLocation.latitude == 0.0 && userLocation.longitude == 0.0
            ? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            : userLocation
        
        Task {
            await cacheManager.downloadTilesForRegion(
                center: center,
                radius: cacheRadius,
                minZoom: minZoom,
                maxZoom: maxZoom
            )
        }
    }
}

#Preview {
    let manager = LocationManager()
    
    return MapView(locationManager: manager)
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
