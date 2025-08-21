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
            
            // Note about download location
            VStack(spacing: 8) {
                Text("Download Tiles")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                
                Text("Use the Map view to download tiles for specific areas. Toggle the cache mode button in the Map view to access download controls.")
                    .font(.callout)
                    .foregroundColor(.prussianBlueLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(Color.prussianSoft.opacity(0.3))
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
        .onAppear {
            cacheManager.updateCacheStats()
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