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
    var x: Int
    var y: Int
    var z: Int
    var data: Data
    var timestamp: Date
    var url: String
    
    init(x: Int, y: Int, z: Int, data: Data, url: String) {
        self.x = x
        self.y = y
        self.z = z
        self.data = data
        self.timestamp = Date()
        self.url = url
    }
    
    /// Unique identifier for the tile
    var tileKey: String {
        return "\(z)/\(x)/\(y)"
    }
    
    /// Check if tile is expired (older than 7 days)
    var isExpired: Bool {
        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        return Date().timeIntervalSince(timestamp) > expirationInterval
    }
}