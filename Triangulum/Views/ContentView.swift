//
//  ContentView.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var barometerManager = BarometerManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var accelerometerManager = AccelerometerManager()
    @StateObject private var gyroscopeManager = GyroscopeManager()
    @StateObject private var magnetometerManager = MagnetometerManager()
    @StateObject private var snapshotManager = SnapshotManager()
    @State private var showSnapshotDialog = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 20) {
                BarometerView(barometerManager: barometerManager)
                
                LocationView(locationManager: locationManager)
                
                AccelerometerView(accelerometerManager: accelerometerManager)
                
                GyroscopeView(gyroscopeManager: gyroscopeManager)
                
                MagnetometerView(magnetometerManager: magnetometerManager)
                
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
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Sensor Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
            accelerometerManager.startAccelerometerUpdates()
            gyroscopeManager.startGyroscopeUpdates()
            magnetometerManager.startMagnetometerUpdates()
        }
        .onDisappear {
            barometerManager.stopBarometerUpdates()
            locationManager.stopLocationUpdates()
            accelerometerManager.stopAccelerometerUpdates()
            gyroscopeManager.stopGyroscopeUpdates()
            magnetometerManager.stopMagnetometerUpdates()
        }
        .alert("Snapshot Taken", isPresented: $showSnapshotDialog) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sensor snapshot has been saved to your footprints.")
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
        snapshotManager.addSnapshot(snapshot)
        showSnapshotDialog = true
    }
}

#Preview {
    ContentView()
}
