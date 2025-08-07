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
                    .background(Color.prussianBlueLight)
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Sensor Readings")
                            .font(.headline)
                            .foregroundColor(.prussianBlueDark)
                        Spacer()
                        Button(action: toggleRecording) {
                            Text(isRecording ? "Stop" : "Start")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(isRecording ? Color.prussianError : Color.prussianSuccess)
                                .cornerRadius(20)
                        }
                    }
                    
                    List {
                        ForEach(sensorReadings.prefix(10)) { reading in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(reading.sensorType.displayName)
                                        .font(.caption)
                                        .foregroundColor(.prussianBlueLight)
                                    Spacer()
                                    Text(reading.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption)
                                        .foregroundColor(.prussianBlueLight)
                                }
                                Text("\(reading.value, specifier: "%.2f") \(reading.unit)")
                                    .font(.body)
                                    .foregroundColor(.prussianBlueDark)
                            }
                            .padding(.vertical, 4)
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
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Sensor Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .foregroundColor(.white)
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                            .foregroundColor(.white)
                    }
                }
            }
        } detail: {
            Text("Select an item")
                .foregroundColor(.prussianBlueDark)
                .background(Color.prussianSoft.ignoresSafeArea())
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
