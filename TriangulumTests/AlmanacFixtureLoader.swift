//
//  AlmanacFixtureLoader.swift
//  TriangulumTests
//

import Foundation

/// Loads Almanac test fixtures relative to this source file, not the app or
/// test bundle: fixtures are test-only source artifacts with no runtime
/// resource membership.
enum AlmanacFixtureLoader {
    enum FixtureError: Error, Equatable {
        case empty(String)
    }

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Almanac", isDirectory: true)

    static func data(_ relativePath: String) throws -> Data {
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        guard !data.isEmpty else { throw FixtureError.empty(relativePath) }
        return data
    }
}
