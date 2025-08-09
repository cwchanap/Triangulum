//
//  TriangulumApp.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import SwiftUI
import SwiftData

@main
struct TriangulumApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            SensorReading.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to create ModelContainer: \(error)")
            // Try to create an in-memory container as fallback
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Could not create fallback ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
