import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    @State private var isTrackingUser = false
    
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
                
                Button(action: centerOnUser) {
                    Image(systemName: isTrackingUser ? "location.fill" : "location")
                        .font(.title3)
                        .foregroundColor(.prussianAccent)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
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
        
        if isTrackingUser {
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
        
        withAnimation(.easeInOut(duration: 1.0)) {
            position = .region(
                MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
        
        isTrackingUser.toggle()
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