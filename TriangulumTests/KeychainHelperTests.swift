//
//  KeychainHelperTests.swift
//  TriangulumTests
//
//  Tests for KeychainHelper secure storage operations
//

import Testing
import Foundation
@testable import Triangulum

@Suite(.serialized)
struct KeychainHelperTests {
    private let testKey = "com.triangulum.test.key.\(UUID().uuidString)"

    @Test func testStoreAndRetrieveString() {
        let stored = KeychainHelper.shared.store("test_value", forKey: testKey)
        #expect(stored == true)

        let retrieved = KeychainHelper.shared.retrieve(forKey: testKey)
        #expect(retrieved == "test_value")

        KeychainHelper.shared.delete(testKey)
    }

    @Test func testDeleteKey() {
        KeychainHelper.shared.store("to_delete", forKey: testKey)
        let deleted = KeychainHelper.shared.delete(testKey)
        #expect(deleted == true)

        let retrieved = KeychainHelper.shared.retrieve(forKey: testKey)
        #expect(retrieved == nil)
    }

    @Test func testRetrieveNonExistentKey() {
        let retrieved = KeychainHelper.shared.retrieve(forKey: "nonexistent_key_\(UUID().uuidString)")
        #expect(retrieved == nil)
    }

    @Test func testExistsCheck() {
        #expect(KeychainHelper.shared.exists(forKey: testKey) == false)

        KeychainHelper.shared.store("exists_test", forKey: testKey)
        #expect(KeychainHelper.shared.exists(forKey: testKey) == true)

        KeychainHelper.shared.delete(testKey)
    }

    @Test func testOverwriteExistingKey() {
        KeychainHelper.shared.store("first_value", forKey: testKey)
        KeychainHelper.shared.store("second_value", forKey: testKey)

        let retrieved = KeychainHelper.shared.retrieve(forKey: testKey)
        #expect(retrieved == "second_value")

        KeychainHelper.shared.delete(testKey)
    }

    @Test func testStoreAndRetrieveData() {
        let testData = Data("binary_test".utf8)
        let stored = KeychainHelper.shared.store(testData, forKey: testKey)
        #expect(stored == true)

        let retrieved = KeychainHelper.shared.retrieveData(forKey: testKey)
        #expect(retrieved == testData)

        KeychainHelper.shared.delete(testKey)
    }

    @Test func testDeleteNonExistentKeySucceeds() {
        let deleted = KeychainHelper.shared.delete("nonexistent_key_\(UUID().uuidString)")
        #expect(deleted == true)
    }
}
