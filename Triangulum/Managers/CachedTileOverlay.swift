//
//  CachedTileOverlay.swift
//  Triangulum
//
//  Created by Rovo Dev on 5/8/2025.
//

import Foundation
import MapKit
import UIKit

class CachedTileOverlay: MKTileOverlay {
    private lazy var cacheManager: TileCacheManager = TileCacheManager.shared

    override init(urlTemplate: String?) {
        super.init(urlTemplate: urlTemplate)
        self.canReplaceMapContent = true
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // We override loadTile instead, so this won't be used
        return URL(string: "https://tile.openstreetmap.org/\(path.z)/\(path.x)/\(path.y).png")!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        Task { @MainActor in
            let tileData = await cacheManager.getTile(x: path.x, y: path.y, z: path.z)

            if let data = tileData {
                result(data, nil)
            } else {
                // Return a placeholder tile or error
                result(nil, NSError(domain: "TileError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tile not found"]))
            }
        }
    }
}

class CachedTileOverlayRenderer: MKTileOverlayRenderer {
    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        return true
    }
}
