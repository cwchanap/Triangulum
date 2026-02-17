import SwiftUI
import MapKit

struct MapView: View {
    private static let defaultCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    @ObservedObject var locationManager: LocationManager
    @AppStorage("mapProvider") private var mapProvider = "apple" // "apple" or "osm"
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: Self.defaultCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    @State private var isTrackingUser = false
    @State private var hasCenteredAppleOnce = false
    @State private var isCacheMode = false
    // OSM-specific centering and search state
    @State private var osmCenter: CLLocationCoordinate2D = Self.defaultCoordinate
    @State private var osmSpan: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    @State private var osmRecenterToken: UUID = UUID()
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var searchMessage: String?
    @State private var selectedResultCoordinate: CLLocationCoordinate2D?
    @State private var selectedResultTitle: String?
    @State private var cacheRadius: Double = 1000.0
    @State private var minZoom = 10
    @State private var maxZoom = 16
    @StateObject private var cacheManager = TileCacheManager.shared
    @StateObject private var appleCompleter = AppleSearchCompleter()
    @State private var osmSuggestions: [OSMGeocoder.Result] = []
    @State private var osmAutocompleteTask: Task<Void, Error>?
    @State private var osmVisibleRegion: MKCoordinateRegion?
    @State private var limitToView: Bool = false

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
                    // Toggle cache mode
                    Button {
                        isCacheMode.toggle()
                    } label: {
                        Image(systemName: isCacheMode ? "externaldrive.fill" : "externaldrive")
                            .font(.title3)
                            .foregroundColor(isCacheMode ? .prussianAccent : .prussianBlueLight)
                    }
                }

                Button {
                    centerOnUser()
                } label: {
                    Image(systemName: isTrackingUser ? "location.fill" : "location")
                        .font(.title3)
                        .foregroundColor(.prussianAccent)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // Search bar: OSM uses Nominatim, Apple uses MKLocalSearch
            HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundColor(.prussianBlueLight)
                        TextField("Search places", text: $searchText)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .onSubmit { performSearch() }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchMessage = nil
                                osmSuggestions = []
                                appleCompleter.results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.prussianBlueLight)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.prussianSoft.opacity(0.4))
                    .cornerRadius(10)

                    Button(action: performSearch) {
                        if isSearching {
                            ProgressView().scaleEffect(0.7).tint(.prussianAccent)
                        } else {
                            Text("Search").font(.subheadline).foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSearching ? Color.prussianSoft : Color.prussianAccent)
                    .cornerRadius(10)
                    .disabled(isSearching || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    // Limit to visible region toggle (applies to OSM strictly; Apple is a bias)
                    HStack(spacing: 6) {
                        Toggle("", isOn: $limitToView).labelsHidden()
                        Text("Limit to View").font(.caption2).foregroundColor(.prussianBlueDark)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)

            // Autocomplete suggestions (provider-specific)
            if mapProvider == "osm" && !osmSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<min(osmSuggestions.count, 6), id: \.self) { idx in
                        let item = osmSuggestions[idx]
                        Button {
                            selectOSMSuggestion(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .foregroundColor(.prussianBlueDark)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.prussianBlue.opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 6)
            } else if mapProvider != "osm" && !appleCompleter.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<min(appleCompleter.results.count, 6), id: \.self) { idx in
                        let comp = appleCompleter.results[idx]
                        Button {
                            selectAppleCompletion(comp)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comp.title).font(.subheadline).foregroundColor(.prussianBlueDark)
                                if !comp.subtitle.isEmpty {
                                    Text(comp.subtitle).font(.caption).foregroundColor(.prussianBlueLight)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.prussianBlue.opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            // Cache controls when in cache mode
            if isCacheMode && mapProvider == "osm" {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pan map to desired area, then tap 'Cache This Area'")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text(
                                "\(cacheManager.getCacheInfo().sizeInMB, specifier: "%.1f") MB cached (\(cacheManager.tilesCount) tiles)"
                            )
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

                        Button {
                            Task {
                                await cacheManager.clearCache()
                            }
                        } label: {
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
            } else if locationManager.authorizationStatus == .denied ||
                        locationManager.authorizationStatus == .restricted {
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
                            center: osmCenter,
                            span: osmSpan,
                            enableCaching: isCacheMode,
                            recenterToken: osmRecenterToken,
                            annotationCoordinate: selectedResultCoordinate,
                            annotationTitle: selectedResultTitle,
                            annotationSubtitle: nil,
                            onRegionChanged: { region in
                                Task { @MainActor in
                                    osmVisibleRegion = region
                                }
                            }
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
                                                .background(
                                                    Circle()
                                                        .fill(Color.white.opacity(0.8))
                                                        .frame(width: 30, height: 30)
                                                )
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
                                                    Image(systemName: cacheManager.isDownloading
                                                        ? "arrow.down.circle"
                                                        : "arrow.down.circle.fill"
                                                    )
                                                    Text(cacheManager.isDownloading
                                                        ? "Downloading..."
                                                        : "Cache This Area"
                                                    )
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
                        // Optional: brief search message overlay
                        .overlay(alignment: .top) {
                            if let message = searchMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(8)
                                    .padding(.top, 8)
                            }
                        }
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

                            if let sel = selectedResultCoordinate {
                                Annotation(selectedResultTitle ?? "Result", coordinate: sel) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.prussianAccent)
                                        .shadow(radius: 2)
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

            if locationManager.isAvailable &&
                (locationManager.authorizationStatus == .authorizedWhenInUse ||
                 locationManager.authorizationStatus == .authorizedAlways) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coordinates")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text(
                            "\(locationManager.latitude, specifier: "%.6f")°, \(locationManager.longitude, specifier: "%.6f")°"
                        )
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
        .onChange(of: searchText) { _, newValue in
            handleAutocomplete(for: newValue)
        }
        .onChange(of: mapProvider) { _, _ in
            // Clear suggestions when switching providers
            osmSuggestions = []
            appleCompleter.results = []
        }
        .onAppear {
            // Auto-center on user location when view appears if location is available
            centerOnUserLocationIfAvailable()
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

        // Auto-center on first valid location update, or when tracking is enabled
        let shouldCenter = isTrackingUser || isFirstLocationUpdate()

        if shouldCenter {
            if mapProvider == "osm" {
                osmCenter = userLocation
                osmSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                osmRecenterToken = UUID()
            } else {
                position = .region(
                    MKCoordinateRegion(
                        center: userLocation,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                )
                hasCenteredAppleOnce = true
            }
        }
    }

    private func isFirstLocationUpdate() -> Bool {
        // Check if we're still showing the default San Francisco location
        if mapProvider == "osm" {
            return abs(osmCenter.latitude - Self.defaultCoordinate.latitude) < 0.0001 &&
                abs(osmCenter.longitude - Self.defaultCoordinate.longitude) < 0.0001
        } else {
            // For Apple Maps, use a flag to only auto-center once
            return !hasCenteredAppleOnce
        }
    }

    private func centerOnUserLocationIfAvailable() {
        // Only auto-center if we have a valid location and are still showing default location
        guard locationManager.latitude != 0.0 || locationManager.longitude != 0.0,
              locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways else {
            return
        }

        // Center on user location without enabling tracking mode
        if mapProvider == "osm" {
            osmCenter = userLocation
            osmSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            osmRecenterToken = UUID()
        } else {
            withAnimation(.easeInOut(duration: 1.0)) {
                position = .region(
                    MKCoordinateRegion(
                        center: userLocation,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                )
            }
        }
    }

    private func centerOnUser() {
        guard locationManager.latitude != 0.0 || locationManager.longitude != 0.0 else { return }

        if mapProvider == "osm" {
            // Recenter OSM to current user location without toggling on every location update
            osmCenter = userLocation
            osmSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            osmRecenterToken = UUID()
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
            ? Self.defaultCoordinate
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

// MARK: - OSM Search
extension MapView {
    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchMessage = nil

        if mapProvider == "osm" {
            // Use OSM Nominatim for OSM map provider
            Task {
                let region = osmVisibleRegion ?? MKCoordinateRegion(center: osmCenter, span: osmSpan)
                let results = try await OSMGeocoder.search(query: query, limit: 1, region: region, bounded: limitToView)
                await MainActor.run {
                    isSearching = false
                    guard let first = results.first else {
                        searchMessage = "No results for ‘\(query)’"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { searchMessage = nil }
                        return
                    }
                    osmCenter = first.coordinate
                    osmSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    osmRecenterToken = UUID()
                    searchMessage = first.displayName
                    selectedResultCoordinate = first.coordinate
                    selectedResultTitle = first.displayName
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { searchMessage = nil }
                }
            }
        } else {
            // Use Apple MKLocalSearch for Apple Maps provider
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            // Bias search near current known location if available
            if locationManager.latitude != 0.0 || locationManager.longitude != 0.0 {
                request.region = MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
                )
            }

            let search = MKLocalSearch(request: request)
            search.start { response, error in
                isSearching = false
                if let error = error {
                    searchMessage = "Search error: \(error.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { searchMessage = nil }
                    return
                }

                guard let response = response, !response.mapItems.isEmpty else {
                    searchMessage = "No results for ‘\(query)’"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { searchMessage = nil }
                    return
                }

                let item = response.mapItems[0]
                let coord = item.placemark.coordinate
                withAnimation(.easeInOut(duration: 0.8)) {
                    position = .region(
                        MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        )
                    )
                }
                searchMessage = item.name ?? "Found location"
                selectedResultCoordinate = coord
                selectedResultTitle = item.name ?? "Result"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { searchMessage = nil }
            }
        }
    }

    private func handleAutocomplete(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            osmSuggestions = []
            appleCompleter.results = []
            return
        }

        if mapProvider == "osm" {
            // Debounce OSM calls
            osmAutocompleteTask?.cancel()
            osmAutocompleteTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                let region = osmVisibleRegion ?? MKCoordinateRegion(center: osmCenter, span: osmSpan)
                let results = try await OSMGeocoder.search(query: trimmed, limit: 6, region: region, bounded: limitToView)
                await MainActor.run { osmSuggestions = results }
            }
        } else {
            if locationManager.latitude != 0.0 || locationManager.longitude != 0.0 {
                appleCompleter.region = MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
                )
            }
            appleCompleter.queryFragment = trimmed
        }
    }

    private func selectOSMSuggestion(_ result: OSMGeocoder.Result) {
        osmCenter = result.coordinate
        osmSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        osmRecenterToken = UUID()
        searchMessage = result.displayName
        osmSuggestions = []
        selectedResultCoordinate = result.coordinate
        selectedResultTitle = result.displayName
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { searchMessage = nil }
    }

    private func selectAppleCompletion(_ completion: MKLocalSearchCompletion) {
        let req = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: req)
        isSearching = true
        search.start { response, _ in
            isSearching = false
            if let item = response?.mapItems.first {
                let coord = item.placemark.coordinate
                withAnimation(.easeInOut(duration: 0.8)) {
                    position = .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                }
                searchMessage = item.name ?? completion.title
                selectedResultCoordinate = coord
                selectedResultTitle = item.name ?? completion.title
                appleCompleter.results = []
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { searchMessage = nil }
            }
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
