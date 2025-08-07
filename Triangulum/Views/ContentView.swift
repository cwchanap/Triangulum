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
    @Query private var items: [Item]
    @Query private var sensorReadings: [SensorReading]
    @StateObject private var barometerManager = BarometerManager()
    @State private var isRecording = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 20) {
                BarometerView(barometerManager: barometerManager)
                
                Divider()
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Sensor Readings")
                            .font(.headline)
                        Spacer()
                        Button(action: toggleRecording) {
                            Text(isRecording ? "Stop" : "Start")
                                .foregroundColor(isRecording ? .red : .green)
                        }
                    }
                    
                    List {
                        ForEach(sensorReadings.prefix(10)) { reading in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(reading.sensorType.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(reading.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("\(reading.value, specifier: "%.2f") \(reading.unit)")
                                    .font(.body)
                            }
                        }
                        .onDelete(perform: deleteReadings)
                        
                        ForEach(items) { item in
                            NavigationLink {
                                Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                            } label: {
                                Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
            .padding()
            .navigationTitle("Sensor Monitor")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
        .onAppear {
            barometerManager.startBarometerUpdates()
        }
        .onDisappear {
            barometerManager.stopBarometerUpdates()
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
    
    private func deleteReadings(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sensorReadings[index])
            }
        }
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        
        if isRecording {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if !self.isRecording {
                    timer.invalidate()
                    return
                }
                
                let reading = SensorReading(
                    sensorType: .barometer,
                    value: self.barometerManager.pressure,
                    unit: "kPa"
                )
                self.modelContext.insert(reading)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
