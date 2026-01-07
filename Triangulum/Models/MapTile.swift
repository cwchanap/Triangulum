//
//  MapTile.swift
//  Triangulum
//
//  Created by Rovo Dev on 5/8/2025.
//

import Foundation
import SwiftData

@Model
final class MapTile {
    var tileX: Int
    var tileY: Int
    var tileZ: Int
    var data: Data
    var timestamp: Date
    var url: String

    init(tileX: Int, tileY: Int, tileZ: Int, data: Data, url: String) {
        self.tileX = tileX
        self.tileY = tileY
        self.tileZ = tileZ
        self.data = data
        self.timestamp = Date()
        self.url = url
    }

    /// Unique identifier for the tile
    var tileKey: String {
        return "\(tileZ)/\(tileX)/\(tileY)"
    }

    /// Check if tile is expired (older than 7 days)
    var isExpired: Bool {
        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        return Date().timeIntervalSince(timestamp) > expirationInterval
    }
}
