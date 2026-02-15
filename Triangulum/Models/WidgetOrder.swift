//
//  WidgetOrder.swift
//  Triangulum
//
//  Created by Rovo Dev on 10/8/2025.
//

import Foundation

enum WidgetType: String, CaseIterable, Identifiable {
    case barometer
    case location
    case weather
    case satellite
    case accelerometer
    case gyroscope
    case magnetometer


    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barometer: return "Barometer"
        case .location: return "Location"
        case .weather: return "Weather"
        case .satellite: return "Satellite"
        case .accelerometer: return "Accelerometer"
        case .gyroscope: return "Gyroscope"
        case .magnetometer: return "Magnetometer"
        }
    }

    var iconName: String {
        switch self {
        case .barometer: return "barometer"
        case .location: return "location.fill"
        case .weather: return "cloud.sun.fill"
        case .satellite: return "antenna.radiowaves.left.and.right"
        case .accelerometer: return "gyroscope"
        case .gyroscope: return "gyroscope"
        case .magnetometer: return "magnet.fill"
        }
    }
}

class WidgetOrderManager: ObservableObject {
    @Published private(set) var widgetOrder: [WidgetType] = []

    private let userDefaults: UserDefaults
    private let widgetOrderKey = "widgetOrder"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadWidgetOrder()
    }

    private func loadWidgetOrder() {
        var needsSave = false

        if let savedOrder = userDefaults.stringArray(forKey: widgetOrderKey) {
            let savedTypes = savedOrder.compactMap { WidgetType(rawValue: $0) }
            var mergedOrder = savedTypes

            let missingTypes = WidgetType.allCases.filter { !savedTypes.contains($0) }
            if !missingTypes.isEmpty {
                mergedOrder.append(contentsOf: missingTypes)
                needsSave = true
            }

            if savedTypes.count != savedOrder.count {
                needsSave = true
            }

            widgetOrder = mergedOrder
        }

        // If no saved order or missing widgets, use default order
        if widgetOrder.isEmpty {
            widgetOrder = WidgetType.allCases
            needsSave = true
        }

        if needsSave {
            saveWidgetOrder()
        }
    }

    private func saveWidgetOrder() {
        let orderStrings = widgetOrder.map { $0.rawValue }
        userDefaults.set(orderStrings, forKey: widgetOrderKey)
    }

    func moveWidget(from source: IndexSet, to destination: Int) {
        widgetOrder.move(fromOffsets: source, toOffset: destination)
        saveWidgetOrder()
    }
}
