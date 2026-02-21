//
//  Item.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import Foundation
import SwiftData

/// Legacy placeholder model retained for SwiftData schema compatibility.
///
/// This model was part of the original schema registered with `ModelContainer`.
/// Removing it without a versioned migration plan causes SwiftData to fail
/// opening existing on-device stores, falling back to in-memory storage and
/// losing persisted tile cache, pressure history, and sensor readings.
/// Keep it in the schema until an explicit `SchemaMigrationPlan` is in place.
@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
