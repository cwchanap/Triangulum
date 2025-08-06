//
//  Item.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
