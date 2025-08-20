//
//  MapCacheView.swift
//  Triangulum
//
//  Created by Rovo Dev on 5/8/2025.
//

import SwiftUI
import MapKit

struct MapCacheView: View {
    @StateObject private var cacheManager = TileCacheManager.shared
    @ObservedObject var locationManager: LocationManager
    @State private var downloadRadius: Double = 1000 // meters
    @State private var minZoom: Int = 10
    @State private var maxZoom: Int = 16
    @State private var showingDownloadAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "externaldrive")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Map Cache")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }
            .padding(.horizontal)
            
            // Cache Statistics
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cache Size")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text("\(cacheManager.getCacheInfo().sizeInMB, specifier: "%.1f") MB")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.prussianBlueDark)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Tiles Cached")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text("\(cacheManager.tilesCount)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.prussianBlueDark)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.8))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.prussianBlue.opacity(0.2), lineWidth: 1)
                )
            }
            
            // Download Controls
            VStack(spacing: 16) {
                Text("Download Tiles for Current Area")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Radius:")
                            .font(.subheadline)
                            .foregroundColor(.prussianBlueLight)
                        Spacer()
                        Text("\(Int(downloadRadius)) meters")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.prussianBlueDark)
                    }
                    
                    Slider(value: $downloadRadius, in: 500...10000, step: 500)
                        .tint(.prussianAccent)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Min Zoom")
                            .font(.subheadline)
                            .foregroundColor(.prussianBlueLight)
                        Picker("Min Zoom", selection: $minZoom) {
                            ForEach(8...18, id: \.self) { zoom in
                                Text("\(zoom)").tag(zoom)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("Max Zoom")
                            .font(.subheadline)
                            .foregroundColor(.prussianBlueLight)
                        Picker("Max Zoom", selection: $maxZoom) {
                            ForEach(8...18, id: \.self) { zoom in
                                Text("\(zoom)").tag(zoom)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                if cacheManager.isDownloading {
                    VStack(spacing: 8) {
                        ProgressView(value: cacheManager.downloadProgress)
                            .tint(.prussianAccent)
                        Text("Downloading... \(Int(cacheManager.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                    }
                } else {
                    Button(action: {
                        showingDownloadAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Download Tiles")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.prussianAccent, .prussianBlue]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                    }
                    .disabled(locationManager.latitude == 0.0 && locationManager.longitude == 0.0)
                }
            }
            .padding()
            .background(Color.white.opacity(0.8))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.prussianBlue.opacity(0.2), lineWidth: 1)
            )
            
            // Cache Management
            VStack(spacing: 12) {
                Text("Cache Management")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                
                Button(action: {
                    Task {
                        await cacheManager.clearCache()
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Cache")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.prussianError)
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.white.opacity(0.8))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.prussianBlue.opacity(0.2), lineWidth: 1)
            )
            
            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.white, Color.prussianSoft]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .alert("Download Tiles", isPresented: $showingDownloadAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Download") {
                downloadTiles()
            }
        } message: {
            Text("This will download map tiles for a \(Int(downloadRadius))m radius around your current location. This may use significant data and storage.")
        }
        .onAppear {
            cacheManager.updateCacheStats()
        }
    }
    
    private func downloadTiles() {
        let center = CLLocationCoordinate2D(
            latitude: locationManager.latitude,
            longitude: locationManager.longitude
        )
        
        Task {
            await cacheManager.downloadTilesForRegion(
                center: center,
                radius: downloadRadius,
                minZoom: minZoom,
                maxZoom: maxZoom
            )
        }
    }
}

#Preview {
    let manager = LocationManager()
    
    return MapCacheView(locationManager: manager)
        .onAppear {
            manager.latitude = 37.7749
            manager.longitude = -122.4194
            manager.isAvailable = true
            manager.authorizationStatus = .authorizedWhenInUse
        }
}