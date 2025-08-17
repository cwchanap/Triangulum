//
//  ContentView.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationManager: LocationManager
    @StateObject private var barometerManager: BarometerManager
    @StateObject private var accelerometerManager = AccelerometerManager()
    @StateObject private var gyroscopeManager = GyroscopeManager()
    @StateObject private var magnetometerManager = MagnetometerManager()
    @StateObject private var snapshotManager = SnapshotManager()
    @State private var showSnapshotDialog = false
    @State private var showEnhancedSnapshotDialog = false
    @State private var currentSnapshot: SensorSnapshot?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    @AppStorage("showBarometerWidget") private var showBarometerWidget = true
    @AppStorage("showLocationWidget") private var showLocationWidget = true
    @AppStorage("showAccelerometerWidget") private var showAccelerometerWidget = true
    @AppStorage("showGyroscopeWidget") private var showGyroscopeWidget = true
    @AppStorage("showMagnetometerWidget") private var showMagnetometerWidget = true

    init() {
        let lm = LocationManager()
        _locationManager = StateObject(wrappedValue: lm)
        _barometerManager = StateObject(wrappedValue: BarometerManager(locationManager: lm))
    }

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(spacing: 20) {
                    if showBarometerWidget {
                        BarometerView(barometerManager: barometerManager)
                    }
                    
                    if showLocationWidget {
                        LocationView(locationManager: locationManager)
                    }
                    
                    if showAccelerometerWidget {
                        AccelerometerView(accelerometerManager: accelerometerManager)
                    }
                    
                    if showGyroscopeWidget {
                        GyroscopeView(gyroscopeManager: gyroscopeManager)
                    }
                    
                    if showMagnetometerWidget {
                        MagnetometerView(magnetometerManager: magnetometerManager)
                    }
                    
                    HStack {
                        Spacer()
                        Button(action: takeSnapshot) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.prussianBlue)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
            }
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Sensor Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink(destination: PreferencesView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    NavigationLink(destination: FootprintView(snapshotManager: snapshotManager)) {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
            }
        } detail: {
            Color.prussianSoft.ignoresSafeArea()
        }
        .onAppear {
            barometerManager.startBarometerUpdates()
            locationManager.startLocationUpdates()
            // TODO: Temporarily disabled until privacy permissions are properly configured
            // accelerometerManager.startAccelerometerUpdates()
            // gyroscopeManager.startGyroscopeUpdates()
            // magnetometerManager.startMagnetometerUpdates()
        }
        .onDisappear {
            barometerManager.stopBarometerUpdates()
            locationManager.stopLocationUpdates()
            // accelerometerManager.stopAccelerometerUpdates()
            // gyroscopeManager.stopGyroscopeUpdates()
            // magnetometerManager.stopMagnetometerUpdates()
        }
        .sheet(isPresented: $showEnhancedSnapshotDialog) {
            SnapshotCreationView(
                snapshot: $currentSnapshot,
                snapshotManager: snapshotManager,
                selectedPhotos: $selectedPhotos,
                isPresented: $showEnhancedSnapshotDialog
            )
        }
    }

    
    private func takeSnapshot() {
        let snapshot = SensorSnapshot(
            barometerManager: barometerManager,
            locationManager: locationManager,
            accelerometerManager: accelerometerManager,
            gyroscopeManager: gyroscopeManager,
            magnetometerManager: magnetometerManager
        )
        currentSnapshot = snapshot
        showEnhancedSnapshotDialog = true
    }
}

struct SnapshotCreationView: View {
    @Binding var snapshot: SensorSnapshot?
    let snapshotManager: SnapshotManager
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var isPresented: Bool
    
    @State private var tempSelectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Success Icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.prussianSuccess)
                    .padding(.top, 20)
                
                // Title and Message
                VStack(spacing: 8) {
                    Text("Snapshot Captured!")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.prussianBlueDark)
                    
                    Text("Sensor data has been recorded at \(snapshot?.timestamp.formatted(date: .omitted, time: .shortened) ?? "now")")
                        .font(.body)
                        .foregroundColor(.prussianBlueLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Photo Section
                VStack(spacing: 16) {
                    HStack {
                        Text("📷 Add Photos (Optional)")
                            .font(.headline)
                            .foregroundColor(.prussianBlueDark)
                        
                        Spacer()
                        
                        PhotosPicker(
                            selection: $tempSelectedPhotos,
                            maxSelectionCount: 5,
                            matching: .images
                        ) {
                            HStack {
                                Image(systemName: "plus")
                                Text("Select Photos")
                            }
                            .font(.callout)
                            .foregroundColor(.prussianBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.prussianBlueLight.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    if !tempSelectedPhotos.isEmpty {
                        Text("\(tempSelectedPhotos.count) photo(s) selected")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                    } else {
                        Text("You can add photos from your library to this snapshot")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                            .italic()
                    }
                    
                    if isProcessingPhotos {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing photos...")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.8))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: saveSnapshot) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Save Snapshot")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.prussianBlue)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessingPhotos)
                    
                    Button("Skip Photos", action: saveSnapshotWithoutPhotos)
                        .font(.callout)
                        .foregroundColor(.prussianBlueLight)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("New Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                        tempSelectedPhotos.removeAll()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onChange(of: tempSelectedPhotos) { newPhotos in
            if !newPhotos.isEmpty {
                isProcessingPhotos = true
            }
        }
    }
    
    private func saveSnapshot() {
        guard let snapshot = snapshot else { return }
        
        // Add the snapshot first
        snapshotManager.addSnapshot(snapshot)
        
        // Then process photos if any
        if !tempSelectedPhotos.isEmpty {
            Task {
                await processSelectedPhotos(for: snapshot.id)
                await MainActor.run {
                    finishSaving()
                }
            }
        } else {
            finishSaving()
        }
    }
    
    private func saveSnapshotWithoutPhotos() {
        guard let snapshot = snapshot else { return }
        snapshotManager.addSnapshot(snapshot)
        finishSaving()
    }
    
    private func finishSaving() {
        isPresented = false
        tempSelectedPhotos.removeAll()
        isProcessingPhotos = false
    }
    
    private func processSelectedPhotos(for snapshotID: UUID) async {
        for photoItem in tempSelectedPhotos {
            do {
                if let data = try await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        snapshotManager.addPhoto(to: snapshotID, image: image)
                    }
                }
            } catch {
                print("Failed to process photo: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}
