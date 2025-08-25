//
//  WidgetOrder.swift
//  Triangulum
//
//  Created by Rovo Dev on 10/8/2025.
//

import Foundation

enum WidgetType: String, CaseIterable, Identifiable {
    case barometer = "barometer"
    case location = "location"
    case weather = "weather"
    case accelerometer = "accelerometer"
    case gyroscope = "gyroscope"
    case magnetometer = "magnetometer"
    case map = "map"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .barometer: return "Barometer"
        case .location: return "Location"
        case .weather: return "Weather"
        case .accelerometer: return "Accelerometer"
        case .gyroscope: return "Gyroscope"
        case .magnetometer: return "Magnetometer"
        case .map: return "Map"
        }
    }
    
    var iconName: String {
        switch self {
        case .barometer: return "barometer"
        case .location: return "location.fill"
        case .weather: return "cloud.sun.fill"
        case .accelerometer: return "gyroscope"
        case .gyroscope: return "gyroscope"
        case .magnetometer: return "magnet.fill"
        case .map: return "map.fill"
        }
    }
}

class WidgetOrderManager: ObservableObject {
    @Published var widgetOrder: [WidgetType] = []
    
    private let userDefaults = UserDefaults.standard
    private let widgetOrderKey = "widgetOrder"
    
    init() {
        loadWidgetOrder()
    }
    
    private func loadWidgetOrder() {
        if let savedOrder = userDefaults.stringArray(forKey: widgetOrderKey) {
            widgetOrder = savedOrder.compactMap { WidgetType(rawValue: $0) }
        }
        
        // If no saved order or missing widgets, use default order
        if widgetOrder.isEmpty || widgetOrder.count != WidgetType.allCases.count {
            widgetOrder = WidgetType.allCases
            saveWidgetOrder()
        }
    }
    
    func saveWidgetOrder() {
        let orderStrings = widgetOrder.map { $0.rawValue }
        userDefaults.set(orderStrings, forKey: widgetOrderKey)
    }
    
    func moveWidget(from source: IndexSet, to destination: Int) {
        widgetOrder.move(fromOffsets: source, toOffset: destination)
        saveWidgetOrder()
    }
}